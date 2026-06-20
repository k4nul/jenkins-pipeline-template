param(
    [string]$RepoRoot,
    [string[]]$EnvironmentPreset,
    [string]$OutputDirectory = "out/jenkins/validation",
    [ValidateSet("text", "json")]
    [string]$Format = "text"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-job-common.ps1")
. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-validation-assertions.ps1")

$context = Initialize-JenkinsValidationContext `
    -RepoRoot $RepoRoot `
    -DefaultRoot (Join-Path -Path $PSScriptRoot -ChildPath "..") `
    -RequestedPresets $EnvironmentPreset `
    -OutputDirectory $OutputDirectory `
    -MissingPresetMessage "No environment presets were found for Jenkins validation."

$root = $context.Root
$jobPlanScript = $context.Paths.JobPlanScript
$jobDslScript = $context.Paths.JobDslScript
$serviceValidationScript = $context.Paths.ServiceValidationScript
$bundlePromotionScript = $context.Paths.BundlePromotionScript
$seedJobPath = $context.Paths.SeedJobPath
$deliveryJobPath = $context.Paths.DeliveryJobPath
$promotionJobPath = $context.Paths.PromotionJobPath
$presets = @($context.Presets)
$resolvedOutputDirectory = $context.OutputDirectory
$servicePlan = $context.ServicePlan
$serviceIndex = $context.ServiceIndex

Assert-RepoOutputPathCaseBoundary -Root $root

$results = New-Object System.Collections.Generic.List[object]

foreach ($preset in $presets) {
    $plan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = @($preset)
        Format = "json"
    }

    Assert-JenkinsPresetJobPlan -Plan $plan -Preset $preset -ServiceIndex $serviceIndex

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

$explicitScmPreset = [string]$presets[0]
$explicitScmDslPath = Join-Path $resolvedOutputDirectory ("{0}-explicit-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "git@example.invalid:org/repo.git" `
    -BranchSpec "*/feature/quote'safe" `
    -ScmCredentialsId "jenkins-scm'credentials" `
    -OutputPath $explicitScmDslPath 6>$null | Out-Null
Assert-ExplicitScmDsl -DslPath $explicitScmDslPath
Assert-JobDslScmInputValidation `
    -ScriptPath $jobDslScript `
    -Root $root `
    -OutputDirectory $resolvedOutputDirectory `
    -Preset $explicitScmPreset
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
Assert-PromotionArchiveEntrySafety `
    -PromotionScript $bundlePromotionScript `
    -Root $root `
    -OutputDirectory $resolvedOutputDirectory

& $serviceValidationScript -RepoRoot $root 6>$null | Out-Null

$serviceJobFixture = New-JenkinsServiceJobFixtureContext `
    -Root $root `
    -OutputDirectory $resolvedOutputDirectory

$serviceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    SelectionName = "service-job-fixture"
    Profile = "web-platform"
    Applications = @("nginx-web")
    Format = "json"
}
Assert-JenkinsServiceJobFixturePlan -Plan $serviceJobFixturePlan

& $serviceJobFixture.JobDslScript `
    -RepoRoot $serviceJobFixture.Root `
    -SelectionName "service-job-fixture" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -OutputPath $serviceJobFixture.ServiceJobDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixture.ServiceJobDslPath -Plan $serviceJobFixturePlan -Preset "service-job-fixture"

$sharedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    ServiceJobRoot = $serviceJobFixture.SharedServiceJobRoot
    Format = "json"
}
Assert-JenkinsServiceJobSharedPresetPlan -Plan $sharedServiceJobFixturePlan -ExpectedServiceJobRoot $serviceJobFixture.SharedServiceJobRoot

& $serviceJobFixture.JobDslScript `
    -RepoRoot $serviceJobFixture.Root `
    -EnvironmentPreset @("fixture-alpha", "fixture-beta") `
    -ServiceJobRoot $serviceJobFixture.SharedServiceJobRoot `
    -OutputPath $serviceJobFixture.SharedServiceJobDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixture.SharedServiceJobDslPath -Plan $sharedServiceJobFixturePlan -Preset "shared-service-job-fixture"
Assert-ServiceJobSharedPresetDsl -Plan $sharedServiceJobFixturePlan -DslPath $serviceJobFixture.SharedServiceJobDslPath -ExpectedServiceJobRoot $serviceJobFixture.SharedServiceJobRoot

$skippedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    SkipServiceJobs = $true
    Format = "json"
}
Assert-JenkinsServiceJobsSkippedPlan -Plan $skippedServiceJobFixturePlan

& $serviceJobFixture.ServiceValidationScript -RepoRoot $serviceJobFixture.Root 6>$null | Out-Null
Assert-MissingServiceJenkinsfileValidationFails -Root $root -OutputDirectory $resolvedOutputDirectory
Assert-UnsafeServiceCatalogNamesFail -Root $root -OutputDirectory $resolvedOutputDirectory

$summary = [PSCustomObject]@{
    Status = "passed"
    Presets = @($presets)
    PresetCount = $presets.Count
    ServiceCount = @($servicePlan.Services).Count
    OutputDirectory = $resolvedOutputDirectory
    ExplicitScmFixture = $explicitScmDslPath
    ServiceJobFixture = $serviceJobFixture.ServiceJobDslPath
    SharedServiceJobFixture = $serviceJobFixture.SharedServiceJobDslPath
    SeedJobSafety = "passed"
    OutputPathCaseBoundary = "passed"
    PromotionArchiveEntrySafety = "passed"
    RuntimeContract = "passed"
    Results = @($results.ToArray())
}

if ($Format -eq "json") {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output ("Jenkins Job DSL validation passed for presets: {0}" -f ($presets -join ", "))
    Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
    Write-Output "Validated unsafe SCM inputs fail closed before Job DSL generation."
    Write-Output ("Validated Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixture.ServiceJobDslPath)
    Write-Output "Validated missing Jenkinsfile-backed service jobs fail closed."
    Write-Output "Validated public preset application service catalog coverage."
    Write-Output "Validated seed job SCM apply and destructive delete confirmation guards."
    Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
    Write-Output "Validated repository output paths reject case-variant out roots."
    Write-Output "Validated non-dry-run delivery and promotion deployment approval guards."
    Write-Output "Validated promotion archive entries fail closed before extraction."
    Write-Output "Validated committed Jenkins runtime entrypoints and public-safe values defaults."
    Write-Output ("Validated shared Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixture.SharedServiceJobDslPath)
    Write-Output "Validated SkipServiceJobs suppresses Jenkinsfile-backed service jobs."
    Write-Output "Validated unsafe and duplicate service catalog names fail closed."
    Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
    Write-Output ("Generated ignored Job DSL fixtures under: {0}" -f $resolvedOutputDirectory)
}
