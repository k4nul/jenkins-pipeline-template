param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../scripts/jenkins-job-common.ps1")
. (Join-Path $PSScriptRoot "../scripts/jenkins-validation-assertions.ps1")

function Assert-CustomDirectSelectionPlan {
    param(
        [object]$Plan
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Custom direct selection should produce one selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "Custom direct selection should skip service jobs when requested"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "feature-blue-green" -Message "Custom selection name should be path-safe"
    Assert-Condition -Condition (-not [bool]$selection.UsesPreset) -Message "Custom direct selection should not be marked as preset-backed"
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected "team/bundles/feature-blue-green" -Message "Custom selection should use the requested bundle root"
    Assert-Equal -Actual ([string]$selection.ValidationJobPath) -Expected "team/bundles/feature-blue-green/repository-validation" -Message "Custom validation job path"
    Assert-Equal -Actual ([string]$selection.DeliveryJobPath) -Expected "team/bundles/feature-blue-green/bundle-delivery" -Message "Custom delivery job path"
    Assert-Equal -Actual ([string]$selection.PromotionJobPath) -Expected "team/bundles/feature-blue-green/bundle-promotion" -Message "Custom promotion job path"
    Assert-Equal -Actual ([string]$selection.ValuesFile) -Expected "config/custom-values.env" -Message "Custom values file should be preserved"
    Assert-Equal -Actual ([string]$selection.Version) -Expected "1.2.3" -Message "Custom version should be preserved"
    Assert-Equal -Actual ([string]$selection.BundleOutputPath) -Expected "out/delivery/custom" -Message "Custom bundle output path should be preserved"
    Assert-Equal -Actual ([string]$selection.ArchivePath) -Expected "out/delivery/custom.zip" -Message "Custom archive path should be preserved"
    Assert-Equal -Actual ([string]$selection.PromotionExtractPath) -Expected "out/promotion/custom" -Message "Custom promotion extract path should be preserved"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected "VALIDATION_PROFILE=web-platform" -Message "Custom validation job should expose the profile parameter"
    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected "VALIDATION_APPLICATIONS=nginx-web, whoami" -Message "Custom validation job should expose application parameters"
    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected "VALIDATION_DATA_SERVICES=redis" -Message "Custom validation job should expose data service parameters"
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected "BUNDLE_OUTPUT_PATH=out/delivery/custom" -Message "Custom delivery job should expose the bundle output path"
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected "BUNDLE_ARCHIVE_PATH=out/delivery/custom.zip" -Message "Custom delivery job should expose the archive path"
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_ARCHIVE_PATH=out/delivery/custom.zip" -Message "Custom promotion job should expose the archive path"
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_EXTRACT_PATH=out/promotion/custom" -Message "Custom promotion job should expose the extract path"

    Assert-Condition -Condition (-not (@($validationJob.KeyParameters) -contains "VALIDATION_ENVIRONMENT_PRESET=feature-blue-green")) -Message "Custom validation job should not invent a preset parameter"
    Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message "Custom delivery should depend on validation"
    Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message "Custom promotion should depend on delivery"
}

function Assert-CustomDirectSelectionDsl {
    param(
        [string]$DslPath,
        [object]$Plan
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated custom direct-selection DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "// Service job count: 0" -Message "Custom direct-selection DSL should record that service jobs were skipped"
    Assert-TextContains -Text $dsl -Expected "boolean useLightweightCheckout = false" -Message "Custom direct-selection DSL should honor the lightweight checkout override"
    Assert-TextContains -Text $dsl -Expected "folder('team')" -Message "Custom direct-selection DSL should create the top-level custom folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/bundles')" -Message "Custom direct-selection DSL should create the requested bundle root folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/bundles/feature-blue-green')" -Message "Custom direct-selection DSL should create the sanitized selection folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/services')" -Message "Custom direct-selection DSL should create the requested service root folder"
    Assert-TextNotMatch -Text $dsl -Pattern "pipelineJob\('team/services/" -Message "Custom direct-selection DSL should not generate service jobs when service jobs are skipped"

    foreach ($selection in @($Plan.Selections)) {
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Custom direct-selection DSL should include job {0}" -f $job.Path)
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Custom direct-selection DSL should include Jenkinsfile {0}" -f $job.Jenkinsfile)
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
Assert-ServicePipelinePlan -Plan $servicePlan

$serviceIndex = @{}
foreach ($service in @($servicePlan.Services)) {
    $serviceIndex[[string]$service.Name] = $service
}

foreach ($preset in $presets) {
    $plan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = @($preset)
        Format = "json"
    }

    Assert-JenkinsPresetJobPlan -Plan $plan -Preset $preset -ServiceIndex $serviceIndex

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

$customDirectSelectionPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "feature/blue green"
    Profile = "web-platform"
    Applications = @("nginx-web", "whoami")
    DataServices = @("redis")
    ValuesFile = "config/custom-values.env"
    Version = "1.2.3"
    BundleOutputPath = "out/delivery/custom"
    ArchivePath = "out/delivery/custom.zip"
    PromotionExtractPath = "out/promotion/custom"
    JobRoot = "team/bundles"
    ServiceJobRoot = "team/services"
    SkipServiceJobs = $true
    Format = "json"
}
Assert-CustomDirectSelectionPlan -Plan $customDirectSelectionPlan

$customDirectSelectionDslPath = Join-Path $outputDirectory "custom-direct-selection-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "feature/blue green" `
    -Profile "web-platform" `
    -Applications @("nginx-web", "whoami") `
    -DataServices @("redis") `
    -ValuesFile "config/custom-values.env" `
    -Version "1.2.3" `
    -BundleOutputPath "out/delivery/custom" `
    -ArchivePath "out/delivery/custom.zip" `
    -PromotionExtractPath "out/promotion/custom" `
    -JobRoot "team/bundles" `
    -ServiceJobRoot "team/services" `
    -SkipServiceJobs `
    -UseLightweightCheckout:$false `
    -OutputPath $customDirectSelectionDslPath 6>$null | Out-Null
Assert-CustomDirectSelectionDsl -DslPath $customDirectSelectionDslPath -Plan $customDirectSelectionPlan

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
Write-Output ("Validated custom direct-selection Job DSL fixture: {0}" -f $customDirectSelectionDslPath)
Write-Output "Validated seed job destructive delete confirmation guard."
Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
