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

function Invoke-ScriptExpectingFailure {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments,
        [string]$ExpectedMessage,
        [string]$Message
    )

    $failed = $false
    $failureMessage = ""

    try {
        & $ScriptPath @Arguments 6>$null | Out-Null
    }
    catch {
        $failed = $true
        $failureMessage = [string]$_
    }

    Assert-Condition -Condition $failed -Message $Message
    Assert-TextContains -Text $failureMessage -Expected $ExpectedMessage -Message ("Failure should explain rejected Job DSL path input: {0}" -f $ExpectedMessage)
}

function Assert-NestedRootPlanAndDsl {
    param(
        [object]$Plan,
        [string]$DslPath
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Nested-root selection should produce one selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "Nested-root selection should skip service jobs"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "qa-blue-canary" -Message "Nested-root selection name should be path-safe"
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected "team/platform/bundles/qa-blue-canary" -Message "Nested bundle folder path"
    Assert-Equal -Actual ([string]$selection.ValidationJobPath) -Expected "team/platform/bundles/qa-blue-canary/repository-validation" -Message "Nested validation job path"
    Assert-Equal -Actual ([string]$selection.DeliveryJobPath) -Expected "team/platform/bundles/qa-blue-canary/bundle-delivery" -Message "Nested delivery job path"
    Assert-Equal -Actual ([string]$selection.PromotionJobPath) -Expected "team/platform/bundles/qa-blue-canary/bundle-promotion" -Message "Nested promotion job path"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message "Nested-root delivery should depend on validation"
    Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message "Nested-root promotion should depend on delivery"

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated nested-root DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    foreach ($folderPath in @(
        "team",
        "team/platform",
        "team/platform/bundles",
        "team/platform/bundles/qa-blue-canary",
        "team/services",
        "team/services/shared"
    )) {
        Assert-TextContains -Text $dsl -Expected ("folder('{0}')" -f $folderPath) -Message ("Nested-root DSL should include folder {0}" -f $folderPath)
    }

    foreach ($job in @($selection.PipelineJobs)) {
        Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Nested-root DSL should include job {0}" -f $job.Path)
        Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Nested-root DSL should include Jenkinsfile {0}" -f $job.Jenkinsfile)
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
Assert-JobDslScmInputValidation `
    -ScriptPath $jobDslScript `
    -Root $root `
    -OutputDirectory $outputDirectory `
    -Preset $explicitScmPreset

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

$nestedRootPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "qa/blue canary"
    Profile = "web-platform"
    Applications = @("nginx-web", "whoami")
    DataServices = @("redis")
    JobRoot = "team/platform/bundles"
    ServiceJobRoot = "team/services/shared"
    SkipServiceJobs = $true
    Format = "json"
}
$nestedRootDslPath = Join-Path $outputDirectory "nested-root-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "qa/blue canary" `
    -Profile "web-platform" `
    -Applications @("nginx-web", "whoami") `
    -DataServices @("redis") `
    -JobRoot "team/platform/bundles" `
    -ServiceJobRoot "team/services/shared" `
    -SkipServiceJobs `
    -OutputPath $nestedRootDslPath 6>$null | Out-Null
Assert-NestedRootPlanAndDsl -Plan $nestedRootPlan -DslPath $nestedRootDslPath

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobPlanScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "unsafe-root"
        Profile = "web-platform"
        JobRoot = "../team"
        Format = "json"
    } `
    -ExpectedMessage "Jenkins job path segment is not allowed" `
    -Message "Job plan generation should reject parent-directory JobRoot segments"

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobDslScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "unsafe-service-root"
        Profile = "web-platform"
        ServiceJobRoot = 'services/${name}'
        OutputPath = "out/jenkins/tests/public-presets/unsafe-service-root-seed-job-dsl.groovy"
    } `
    -ExpectedMessage "Jenkins job path segment is not allowed" `
    -Message "Job DSL export should reject unsafe ServiceJobRoot segments"

$serviceJobFixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $root -OutputDirectory $outputDirectory
$serviceJobFixturePlanScript = Join-Path $serviceJobFixtureRoot "scripts/show-jenkins-job-plan.ps1"
$serviceJobFixtureDslScript = Join-Path $serviceJobFixtureRoot "scripts/export-jenkins-job-dsl.ps1"
$serviceJobFixtureValidationScript = Join-Path $serviceJobFixtureRoot "scripts/validate-service-pipelines.ps1"
$serviceJobFixtureDslOutputPath = "out/jenkins/tests/service-job-fixture-seed-job-dsl.groovy"
$serviceJobFixtureDslPath = Join-Path $serviceJobFixtureRoot $serviceJobFixtureDslOutputPath

$serviceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixturePlanScript -Arguments @{
    RepoRoot = $serviceJobFixtureRoot
    SelectionName = "service-job-fixture"
    Profile = "web-platform"
    Applications = @("nginx-web")
    Format = "json"
}
Assert-JenkinsServiceJobFixturePlan -Plan $serviceJobFixturePlan

& $serviceJobFixtureDslScript `
    -RepoRoot $serviceJobFixtureRoot `
    -SelectionName "service-job-fixture" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -OutputPath $serviceJobFixtureDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixtureDslPath -Plan $serviceJobFixturePlan -Preset "service-job-fixture"
& $serviceJobFixtureValidationScript -RepoRoot $serviceJobFixtureRoot 6>$null | Out-Null
Assert-MissingServiceJenkinsfileValidationFails -Root $root -OutputDirectory $outputDirectory

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
Assert-JenkinsfileDeploymentApprovalSafety `
    -JenkinsfilePath $deliveryJobPath `
    -DeployParameterName "BUNDLE_DEPLOY" `
    -DryRunParameterName "BUNDLE_DEPLOY_DRY_RUN" `
    -RequireSecretsParameterName "BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY" `
    -RequireStatusParameterName "BUNDLE_REQUIRE_BOOTSTRAP_STATUS"
Assert-JenkinsfileDeploymentApprovalSafety `
    -JenkinsfilePath $promotionJobPath `
    -DeployParameterName "PROMOTION_DEPLOY" `
    -DryRunParameterName "PROMOTION_DEPLOY_DRY_RUN" `
    -RequireSecretsParameterName "PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY" `
    -RequireStatusParameterName "PROMOTION_REQUIRE_BOOTSTRAP_STATUS"

Write-Output ("Jenkins public preset tests passed for presets: {0}" -f ($presets -join ", "))
Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
Write-Output "Validated unsafe SCM inputs fail closed before Job DSL generation."
Write-Output ("Validated custom direct-selection Job DSL fixture: {0}" -f $customDirectSelectionDslPath)
Write-Output ("Validated nested Job DSL root fixture: {0}" -f $nestedRootDslPath)
Write-Output "Validated unsafe Job DSL root segments fail closed."
Write-Output ("Validated Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixtureDslPath)
Write-Output "Validated missing Jenkinsfile-backed service jobs fail closed."
Write-Output "Validated seed job SCM apply and destructive delete confirmation guards."
Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
Write-Output "Validated non-dry-run delivery and promotion deployment approval guards."
