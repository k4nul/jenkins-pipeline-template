param(
    [string]$RepoRoot,
    [string[]]$EnvironmentPreset,
    [string]$OutputDirectory = "out/jenkins/validation",
    [ValidateSet("text", "json")]
    [string]$Format = "text"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "jenkins-job-common.ps1")

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-TextContains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Context
    )

    Assert-Condition -Condition $Text.Contains($Expected) -Message ("{0} is missing expected text: {1}" -f $Context, $Expected)
}

function Get-PresetNames {
    param(
        [string]$Root,
        [string[]]$RequestedPresets
    )

    $normalized = @(Get-NormalizedList -Values $RequestedPresets)
    if ($normalized.Count -gt 0) {
        return @($normalized)
    }

    $presetDirectory = Join-Path $Root "config/environments"
    return @(
        Get-ChildItem -Path $presetDirectory -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
}

function Invoke-JsonScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $json = (& $ScriptPath @Arguments | Out-String).Trim()
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($json)) -Message ("{0} returned empty JSON output." -f $ScriptPath)
    return ($json | ConvertFrom-Json)
}

function Assert-PipelineJob {
    param(
        [object]$Selection,
        [string]$JobName,
        [string]$ExpectedPath,
        [string]$ExpectedJenkinsfile,
        [string[]]$ExpectedKeyParameters
    )

    $job = @($Selection.PipelineJobs | Where-Object { $_.Name -eq $JobName } | Select-Object -First 1)
    Assert-Condition -Condition ($null -ne $job) -Message ("Selection {0} is missing pipeline job {1}." -f $Selection.Name, $JobName)
    Assert-Condition -Condition ([string]$job.Path -eq $ExpectedPath) -Message ("{0} path mismatch. Expected {1}; found {2}." -f $JobName, $ExpectedPath, $job.Path)
    Assert-Condition -Condition ([string]$job.Jenkinsfile -eq $ExpectedJenkinsfile) -Message ("{0} Jenkinsfile mismatch. Expected {1}; found {2}." -f $JobName, $ExpectedJenkinsfile, $job.Jenkinsfile)

    foreach ($parameter in @($ExpectedKeyParameters)) {
        Assert-Condition `
            -Condition (@($job.KeyParameters) -contains $parameter) `
            -Message ("{0} is missing key parameter {1}." -f $ExpectedPath, $parameter)
    }
}

function Assert-JobPlan {
    param(
        [object]$Plan,
        [string]$Preset
    )

    Assert-Condition -Condition ([int]$Plan.SelectionCount -eq 1) -Message ("Preset {0} should produce exactly one bundle selection." -f $Preset)

    $selection = @($Plan.Selections | Select-Object -First 1)
    Assert-Condition -Condition ([string]$selection.Name -eq $Preset) -Message ("Preset {0} produced selection {1}." -f $Preset, $selection.Name)
    Assert-Condition -Condition ([bool]$selection.UsesPreset) -Message ("Preset {0} should be marked as a preset-backed selection." -f $Preset)

    $expectedRoot = "platform/{0}" -f $Preset
    Assert-Condition -Condition ([string]$selection.BundleFolderPath -eq $expectedRoot) -Message ("Preset {0} bundle folder path mismatch." -f $Preset)

    Assert-PipelineJob `
        -Selection $selection `
        -JobName "repository-validation" `
        -ExpectedPath ("{0}/repository-validation" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\repository-validation.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("VALIDATION_ENVIRONMENT_PRESET={0}" -f $Preset),
            "VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY=false"
        )

    Assert-PipelineJob `
        -Selection $selection `
        -JobName "bundle-delivery" `
        -ExpectedPath ("{0}/bundle-delivery" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\bundle-delivery.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("BUNDLE_ENVIRONMENT_PRESET={0}" -f $Preset),
            "BUNDLE_DEPLOY=false"
        )

    Assert-PipelineJob `
        -Selection $selection `
        -JobName "bundle-promotion" `
        -ExpectedPath ("{0}/bundle-promotion" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\bundle-promotion.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("PROMOTION_ENVIRONMENT_PRESET={0}" -f $Preset),
            "PROMOTION_DEPLOY=false",
            "PROMOTION_DEPLOY_DRY_RUN=true"
        )

    Assert-Condition -Condition (@(@($selection.RecommendedFlow) -match "manual approval").Count -gt 0) -Message ("Preset {0} should keep promotion behind manual approval guidance." -f $Preset)
}

function Assert-GeneratedDsl {
    param(
        [string]$DslPath,
        [object]$Plan,
        [string]$Preset
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Expected generated Job DSL was not written: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Context $DslPath
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Context $DslPath
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Context $DslPath
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Context $DslPath
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Context $DslPath
    Assert-TextContains -Text $dsl -Expected "lightweight(useLightweightCheckout)" -Context $DslPath

    Assert-Condition -Condition (-not ($dsl -match "https?://|git@")) -Message ("Generated Job DSL for {0} contains a concrete SCM URL." -f $Preset)
    Assert-Condition -Condition (-not ($dsl -match "credentials\(['""]")) -Message ("Generated Job DSL for {0} contains an inline credentials ID instead of the scmCredentialsId parameter." -f $Preset)
    Assert-Condition -Condition (-not ($dsl -match "branch\(['""]")) -Message ("Generated Job DSL for {0} contains an inline branch spec instead of the branchSpec parameter." -f $Preset)

    foreach ($selection in @($Plan.Selections)) {
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Context $DslPath
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Context $DslPath
        }
    }

    foreach ($serviceJob in @($Plan.ServiceJobs)) {
        Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $serviceJob.Path) -Context $DslPath
        Assert-TextContains -Text $dsl -Expected ([string]$serviceJob.Jenkinsfile).Replace("\", "/") -Context $DslPath
    }
}

function Assert-ServicePipelinePlan {
    param(
        [object]$Plan
    )

    Assert-Condition -Condition (@($Plan.Services).Count -gt 0) -Message "Service pipeline plan should include at least one catalog service."

    foreach ($service in @($Plan.Services)) {
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Name)) -Message "Service pipeline plan contains a service without a name."
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Category)) -Message ("Service {0} is missing a category." -f $service.Name)
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.ImageName)) -Message ("Service {0} is missing an image name." -f $service.Name)
        Assert-Condition -Condition ($null -ne $service.HasJenkinsfile) -Message ("Service {0} is missing HasJenkinsfile metadata." -f $service.Name)
        Assert-Condition -Condition (@($service.RequiredFiles).Count -gt 0) -Message ("Service {0} should declare required files." -f $service.Name)

        if (-not [bool]$service.HasJenkinsfile) {
            Assert-Condition `
                -Condition (@($service.RequiredJenkinsStrings).Count -eq 0) `
                -Message ("Service {0} has Jenkins string assertions but is marked as not Jenkinsfile-backed." -f $service.Name)
        }
    }
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$jobPlanScript = Join-Path $root "scripts/show-jenkins-job-plan.ps1"
$servicePlanScript = Join-Path $root "scripts/show-service-pipeline-plan.ps1"
$jobDslScript = Join-Path $root "scripts/export-jenkins-job-dsl.ps1"
$serviceValidationScript = Join-Path $root "scripts/validate-service-pipelines.ps1"
$presets = @(Get-PresetNames -Root $root -RequestedPresets $EnvironmentPreset)

Assert-Condition -Condition ($presets.Count -gt 0) -Message "No environment presets were found for Jenkins validation."

$resolvedOutputDirectory = Resolve-RepoOutputPath -RepoRoot $root -Path $OutputDirectory
New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null

$results = New-Object System.Collections.Generic.List[object]

foreach ($preset in $presets) {
    $plan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = @($preset)
        Format = "json"
    }

    Assert-JobPlan -Plan $plan -Preset $preset

    $dslPath = Join-Path $resolvedOutputDirectory ("{0}-seed-job-dsl.groovy" -f $preset)
    & $jobDslScript -RepoRoot $root -EnvironmentPreset $preset -OutputPath $dslPath 6>$null | Out-Null
    Assert-GeneratedDsl -DslPath $dslPath -Plan $plan -Preset $preset

    $results.Add([PSCustomObject]@{
        Preset = $preset
        SelectionCount = [int]$plan.SelectionCount
        ServiceJobCount = [int]$plan.ServiceJobCount
        JobDslPath = $dslPath
        Status = "passed"
    }) | Out-Null
}

$servicePlan = Invoke-JsonScript -ScriptPath $servicePlanScript -Arguments @{
    RepoRoot = $root
    Format = "json"
}
Assert-ServicePipelinePlan -Plan $servicePlan
& $serviceValidationScript -RepoRoot $root 6>$null | Out-Null

$summary = [PSCustomObject]@{
    Status = "passed"
    Presets = @($presets)
    PresetCount = $presets.Count
    ServiceCount = @($servicePlan.Services).Count
    OutputDirectory = $resolvedOutputDirectory
    Results = @($results.ToArray())
}

if ($Format -eq "json") {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output ("Jenkins Job DSL validation passed for presets: {0}" -f ($presets -join ", "))
    Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
    Write-Output ("Generated ignored Job DSL fixtures under: {0}" -f $resolvedOutputDirectory)
}
