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
. (Join-Path $PSScriptRoot "jenkins-validation-assertions.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$jobPlanScript = Join-Path $root "scripts/show-jenkins-job-plan.ps1"
$servicePlanScript = Join-Path $root "scripts/show-service-pipeline-plan.ps1"
$jobDslScript = Join-Path $root "scripts/export-jenkins-job-dsl.ps1"
$serviceValidationScript = Join-Path $root "scripts/validate-service-pipelines.ps1"
$seedJobPath = Join-Path $root "jenkins/job-seed.Jenkinsfile"
$deliveryJobPath = Join-Path $root "jenkins/bundle-delivery.Jenkinsfile"
$promotionJobPath = Join-Path $root "jenkins/bundle-promotion.Jenkinsfile"
$presets = @(Get-PresetNames -Root $root -RequestedPresets $EnvironmentPreset)

Assert-Condition -Condition ($presets.Count -gt 0) -Message "No environment presets were found for Jenkins validation."

$resolvedOutputDirectory = Resolve-RepoOutputPath -RepoRoot $root -Path $OutputDirectory
New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null

$servicePlan = Invoke-JsonScript -ScriptPath $servicePlanScript -Arguments @{
    RepoRoot = $root
    Format = "json"
}
Assert-ServicePipelinePlan -Plan $servicePlan

$serviceIndex = @{}
foreach ($service in @($servicePlan.Services)) {
    $serviceIndex[[string]$service.Name] = $service
}

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

$explicitScmPreset = [string]($presets | Select-Object -First 1)
$explicitScmDslPath = Join-Path $resolvedOutputDirectory ("{0}-explicit-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
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

& $serviceValidationScript -RepoRoot $root 6>$null | Out-Null

$summary = [PSCustomObject]@{
    Status = "passed"
    Presets = @($presets)
    PresetCount = $presets.Count
    ServiceCount = @($servicePlan.Services).Count
    OutputDirectory = $resolvedOutputDirectory
    ExplicitScmFixture = $explicitScmDslPath
    SeedJobSafety = "passed"
    Results = @($results.ToArray())
}

if ($Format -eq "json") {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output ("Jenkins Job DSL validation passed for presets: {0}" -f ($presets -join ", "))
    Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
    Write-Output "Validated seed job destructive delete confirmation guard."
    Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
    Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
    Write-Output ("Generated ignored Job DSL fixtures under: {0}" -f $resolvedOutputDirectory)
}
