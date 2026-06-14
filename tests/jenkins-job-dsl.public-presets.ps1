param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../scripts/jenkins-job-common.ps1")
. (Join-Path $PSScriptRoot "../scripts/jenkins-validation-assertions.ps1")

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

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$jobPlanScript = Join-Path $root "scripts/show-jenkins-job-plan.ps1"
$servicePlanScript = Join-Path $root "scripts/show-service-pipeline-plan.ps1"
$jobDslScript = Join-Path $root "scripts/export-jenkins-job-dsl.ps1"
$seedJobPath = Join-Path $root "jenkins/job-seed.Jenkinsfile"
$deliveryJobPath = Join-Path $root "jenkins/bundle-delivery.Jenkinsfile"
$promotionJobPath = Join-Path $root "jenkins/bundle-promotion.Jenkinsfile"
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

$explicitScmPreset = [string]($presets | Select-Object -First 1)
$explicitScmDslPath = Join-Path $outputDirectory ("{0}-explicit-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "example.invalid/org/repo'with-quote.git" `
    -BranchSpec "*/feature/quote'safe" `
    -ScmCredentialsId "jenkins-scm'credentials" `
    -OutputPath $explicitScmDslPath 6>$null | Out-Null
Assert-ExplicitScmDsl -DslPath $explicitScmDslPath
Assert-SeedJobSafety -SeedJobPath $seedJobPath
Assert-JenkinsfileArtifactPathSafety -JenkinsfilePath $seedJobPath -ExpectedParameterNames @("SEED_OUTPUT_PATH")
Assert-JenkinsfileArtifactPathSafety `
    -JenkinsfilePath $deliveryJobPath `
    -ExpectedParameterNames @("BUNDLE_ARCHIVE_PATH") `
    -ExpectedDirectoryParameterNames @("BUNDLE_OUTPUT_PATH") `
    -ExpectedPipelineBoundaryNames @("BUNDLE_OUTPUT_PATH", "BUNDLE_ARCHIVE_PATH")
Assert-JenkinsfileArtifactPathSafety `
    -JenkinsfilePath $promotionJobPath `
    -ExpectedParameterNames @("PROMOTION_ARCHIVE_PATH") `
    -ExpectedDirectoryParameterNames @("PROMOTION_EXTRACT_PATH") `
    -ExpectedPipelineBoundaryNames @("PROMOTION_ARCHIVE_PATH", "PROMOTION_EXTRACT_PATH")

Write-Output ("Jenkins public preset tests passed for presets: {0}" -f ($presets -join ", "))
Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
Write-Output "Validated seed job destructive delete confirmation guard."
Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
