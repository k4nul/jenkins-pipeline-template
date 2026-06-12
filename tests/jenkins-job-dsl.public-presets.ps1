param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw ("Assertion failed: {0}" -f $Message)
    }
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("Assertion failed: {0}. Expected '{1}', found '{2}'." -f $Message, $Expected, $Actual)
    }
}

function Assert-ContainsItem {
    param(
        [object[]]$Values,
        [string]$Expected,
        [string]$Message
    )

    $items = @($Values | ForEach-Object { [string]$_ })
    Assert-Condition -Condition ($items -contains $Expected) -Message $Message
}

function Assert-TextContains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Message
    )

    Assert-Condition -Condition $Text.Contains($Expected) -Message $Message
}

function Assert-TextNotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    Assert-Condition -Condition (-not ($Text -match $Pattern)) -Message $Message
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

function Get-PresetNames {
    param(
        [string]$Root
    )

    $presetDirectory = Join-Path $Root "config/environments"
    return @(
        Get-ChildItem -Path $presetDirectory -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
}

function Get-PipelineJob {
    param(
        [object]$Selection,
        [string]$Name
    )

    $jobs = @($Selection.PipelineJobs | Where-Object { [string]$_.Name -eq $Name })
    Assert-Equal -Actual $jobs.Count -Expected 1 -Message ("Selection {0} should include exactly one {1} job" -f $Selection.Name, $Name)
    return $jobs[0]
}

function Assert-PresetPlan {
    param(
        [object]$Plan,
        [string]$Preset,
        [hashtable]$ServiceIndex
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message ("Preset {0} should produce one selection" -f $Preset)

    $selection = @($Plan.Selections | Select-Object -First 1)
    Assert-Equal -Actual ([string]$selection.Name) -Expected $Preset -Message ("Preset {0} selection name" -f $Preset)
    Assert-Condition -Condition ([bool]$selection.UsesPreset) -Message ("Preset {0} should be preset-backed" -f $Preset)

    $expectedRoot = "platform/{0}" -f $Preset
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected $expectedRoot -Message ("Preset {0} bundle folder" -f $Preset)
    Assert-Equal -Actual ([string]$selection.ValidationJobPath) -Expected ("{0}/repository-validation" -f $expectedRoot) -Message ("Preset {0} validation job path" -f $Preset)
    Assert-Equal -Actual ([string]$selection.DeliveryJobPath) -Expected ("{0}/bundle-delivery" -f $expectedRoot) -Message ("Preset {0} delivery job path" -f $Preset)
    Assert-Equal -Actual ([string]$selection.PromotionJobPath) -Expected ("{0}/bundle-promotion" -f $expectedRoot) -Message ("Preset {0} promotion job path" -f $Preset)

    $validationJob = Get-PipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-PipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-PipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-Equal -Actual ([string]$validationJob.Jenkinsfile) -Expected "jenkins\repository-validation.Jenkinsfile" -Message ("Preset {0} validation Jenkinsfile" -f $Preset)
    Assert-Equal -Actual ([string]$deliveryJob.Jenkinsfile) -Expected "jenkins\bundle-delivery.Jenkinsfile" -Message ("Preset {0} delivery Jenkinsfile" -f $Preset)
    Assert-Equal -Actual ([string]$promotionJob.Jenkinsfile) -Expected "jenkins\bundle-promotion.Jenkinsfile" -Message ("Preset {0} promotion Jenkinsfile" -f $Preset)

    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected ("VALIDATION_ENVIRONMENT_PRESET={0}" -f $Preset) -Message ("Preset {0} validation job should expose its preset parameter" -f $Preset)
    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected "VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY=false" -Message ("Preset {0} validation job should keep bootstrap secret readiness disabled by default" -f $Preset)
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected ("BUNDLE_ENVIRONMENT_PRESET={0}" -f $Preset) -Message ("Preset {0} delivery job should expose its preset parameter" -f $Preset)
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected "BUNDLE_DEPLOY=false" -Message ("Preset {0} delivery job should keep deployment disabled by default" -f $Preset)
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected ("PROMOTION_ENVIRONMENT_PRESET={0}" -f $Preset) -Message ("Preset {0} promotion job should expose its preset parameter" -f $Preset)
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_DEPLOY=false" -Message ("Preset {0} promotion job should keep deployment disabled by default" -f $Preset)
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_DEPLOY_DRY_RUN=true" -Message ("Preset {0} promotion job should default to dry-run deployment" -f $Preset)

    Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message ("Preset {0} delivery should depend on validation" -f $Preset)
    Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message ("Preset {0} promotion should depend on delivery" -f $Preset)
    Assert-Condition -Condition (@(@($selection.RecommendedFlow) -match "manual approval").Count -gt 0) -Message ("Preset {0} should keep promotion behind manual approval guidance" -f $Preset)

    $expectedServiceJobNames = @(
        @($selection.ServiceDirectories) |
            Where-Object { $ServiceIndex.ContainsKey([string]$_) -and [bool]$ServiceIndex[[string]$_].HasJenkinsfile } |
            Sort-Object -Unique
    )
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected $expectedServiceJobNames.Count -Message ("Preset {0} service job count should match Jenkinsfile-backed selected services" -f $Preset)

    foreach ($serviceDirectory in @($selection.ServiceDirectories)) {
        Assert-Condition -Condition $ServiceIndex.ContainsKey([string]$serviceDirectory) -Message ("Preset {0} selected service {1} should exist in the service pipeline plan" -f $Preset, $serviceDirectory)
    }

    foreach ($serviceName in $expectedServiceJobNames) {
        $serviceJob = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq [string]$serviceName } | Select-Object -First 1)
        Assert-Condition -Condition ($null -ne $serviceJob) -Message ("Preset {0} should include a service job for {1}" -f $Preset, $serviceName)
        Assert-Equal -Actual ([string]$serviceJob.Path) -Expected ("services/{0}" -f $serviceName) -Message ("Preset {0} service job path for {1}" -f $Preset, $serviceName)
    }
}

function Assert-GeneratedDsl {
    param(
        [string]$DslPath,
        [object]$Plan,
        [string]$Preset
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated DSL should exist for preset {0}" -f $Preset)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message ("Preset {0} DSL should keep the SCM URL parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Message ("Preset {0} DSL should keep the branch spec parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Message ("Preset {0} DSL should keep credentials unset by default" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message ("Preset {0} DSL should use the credentials parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message ("Preset {0} DSL should use the branch parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "lightweight(useLightweightCheckout)" -Message ("Preset {0} DSL should expose lightweight checkout as a parameter" -f $Preset)

    Assert-TextNotMatch -Text $dsl -Pattern "https?://|git@" -Message ("Preset {0} DSL should not contain a concrete SCM URL" -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message ("Preset {0} DSL should not inline a credentials ID" -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message ("Preset {0} DSL should not inline a branch spec" -f $Preset)

    foreach ($selection in @($Plan.Selections)) {
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Preset {0} DSL should include job {1}" -f $Preset, $job.Path)
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Preset {0} DSL should include Jenkinsfile {1}" -f $Preset, $job.Jenkinsfile)
        }
    }

    foreach ($serviceJob in @($Plan.ServiceJobs)) {
        Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $serviceJob.Path) -Message ("Preset {0} DSL should include service job {1}" -f $Preset, $serviceJob.Path)
        Assert-TextContains -Text $dsl -Expected ([string]$serviceJob.Jenkinsfile).Replace("\", "/") -Message ("Preset {0} DSL should include service Jenkinsfile {1}" -f $Preset, $serviceJob.Jenkinsfile)
    }
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$jobPlanScript = Join-Path $root "scripts/show-jenkins-job-plan.ps1"
$servicePlanScript = Join-Path $root "scripts/show-service-pipeline-plan.ps1"
$jobDslScript = Join-Path $root "scripts/export-jenkins-job-dsl.ps1"
$outputDirectory = Join-Path $root "out/jenkins/tests/public-presets"
$presets = @(Get-PresetNames -Root $root)

Assert-Condition -Condition ($presets.Count -gt 0) -Message "At least one public-safe environment preset should exist."
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$servicePlan = Invoke-JsonScript -ScriptPath $servicePlanScript -Arguments @{
    RepoRoot = $root
    Format = "json"
}
Assert-Condition -Condition (@($servicePlan.Services).Count -gt 0) -Message "Service pipeline plan should include catalog services."

$serviceIndex = @{}
foreach ($service in @($servicePlan.Services)) {
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Name)) -Message "Service pipeline plan should not contain unnamed services."
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Category)) -Message ("Service {0} should declare a category." -f $service.Name)
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.ImageName)) -Message ("Service {0} should declare an image name." -f $service.Name)
    Assert-Condition -Condition (@($service.RequiredFiles).Count -gt 0) -Message ("Service {0} should declare required files." -f $service.Name)

    if (-not [bool]$service.HasJenkinsfile) {
        Assert-Equal -Actual @($service.RequiredJenkinsStrings).Count -Expected 0 -Message ("Service {0} without a Jenkinsfile should not require Jenkinsfile text assertions" -f $service.Name)
    }

    $serviceIndex[[string]$service.Name] = $service
}

foreach ($preset in $presets) {
    $plan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = @($preset)
        Format = "json"
    }

    Assert-PresetPlan -Plan $plan -Preset $preset -ServiceIndex $serviceIndex

    $dslPath = Join-Path $outputDirectory ("{0}-seed-job-dsl.groovy" -f $preset)
    & $jobDslScript -RepoRoot $root -EnvironmentPreset $preset -OutputPath $dslPath 6>$null | Out-Null
    Assert-GeneratedDsl -DslPath $dslPath -Plan $plan -Preset $preset
}

Write-Output ("Jenkins public preset tests passed for presets: {0}" -f ($presets -join ", "))
Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
