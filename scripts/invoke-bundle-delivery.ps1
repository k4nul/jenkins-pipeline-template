param(
    [string]$RepoRoot,
    [string[]]$EnvironmentPreset,
    [string]$Profile = "web-platform",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [string]$ValuesFile = "config/platform-values.env.example",
    [string]$HelmConfigFile = "config/helm-releases.psd1",
    [string]$DockerRegistry,
    [string]$Version = "0.0.0-ci",
    [string]$OutputPath = "out/ci/web-platform",
    [string]$ArchivePath = "out/ci/web-platform.zip",
    [switch]$IncludeJenkins,
    [switch]$PrepareHelmRepos,
    [switch]$IncludeDeferredComponents,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$RequireBootstrapStatus,
    [switch]$CleanOutput,
    [switch]$OverwriteArchive,
    [switch]$SkipRepositoryValidation,
    [switch]$SkipTemplateValidation,
    [switch]$SkipWorkstationValidation,
    [switch]$SkipBundleValidation,
    [switch]$SkipArchive,
    [switch]$DeployBundle,
    [switch]$DeploymentDryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-job-common.ps1")

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path -Path $PSScriptRoot -ChildPath "..")
$resolvedOutputPath = Resolve-RepoOutputPath -RepoRoot $root -Path $OutputPath
$resolvedArchivePath = Resolve-RepoOutputPath -RepoRoot $root -Path $ArchivePath

if ($DeployBundle -and -not $DeploymentDryRun) {
    throw "Non-dry-run bundle deployment is not implemented in this public-safe Jenkins template. Keep DeploymentDryRun enabled or provide a downstream deployment implementation."
}

if ($PrepareHelmRepos) {
    throw "PrepareHelmRepos is a live Helm action and is not implemented by this public-safe bundle delivery contract."
}

if ($RequireBootstrapStatus) {
    throw "RequireBootstrapStatus needs a live cluster and is outside this controller-free bundle delivery contract."
}

if (-not $SkipRepositoryValidation) {
    $validationArguments = @{
        RepoRoot = $root
        Profile = $Profile
        ValuesFile = $ValuesFile
        HelmConfigFile = $HelmConfigFile
        Version = $Version
        SkipPlatformAssetValidation = $true
    }

    $validationPresets = @(Get-NormalizedList -Values $EnvironmentPreset)
    if ($validationPresets.Count -gt 0) {
        $validationArguments["EnvironmentPreset"] = @($validationPresets)
    }
    $validationApplications = @(Get-NormalizedList -Values $Applications)
    if ($validationApplications.Count -gt 0) {
        $validationArguments["Applications"] = @($validationApplications)
    }
    $validationDataServices = @(Get-NormalizedList -Values $DataServices)
    if ($validationDataServices.Count -gt 0) {
        $validationArguments["DataServices"] = @($validationDataServices)
    }
    if ($DockerRegistry) {
        $validationArguments["DockerRegistry"] = $DockerRegistry
    }
    if ($IncludeJenkins) {
        $validationArguments["IncludeJenkins"] = $true
    }
    if ($RequireBootstrapSecretsReady) {
        $validationArguments["RequireBootstrapSecretsReady"] = $true
    }
    if ($SkipTemplateValidation) {
        $validationArguments["SkipTemplateValidation"] = $true
    }
    if ($SkipWorkstationValidation) {
        $validationArguments["SkipWorkstationValidation"] = $true
    }

    & (Join-Path -Path $root -ChildPath "scripts/invoke-repository-validation.ps1") @validationArguments | Out-Null
}

if ((Test-Path -Path $resolvedOutputPath) -and $CleanOutput) {
    Remove-Item -Path $resolvedOutputPath -Recurse -Force
}

if ((Test-Path -Path $resolvedOutputPath) -and -not $CleanOutput) {
    throw ("OutputPath already exists. Pass -CleanOutput to replace it: {0}" -f $OutputPath)
}

New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null

$planArguments = @{
    RepoRoot = $root
    Profile = $Profile
    ValuesFile = $ValuesFile
    Version = $Version
    Format = "json"
}

$normalizedPresets = @(Get-NormalizedList -Values $EnvironmentPreset)
if ($normalizedPresets.Count -gt 0) {
    $planArguments["EnvironmentPreset"] = @($normalizedPresets)
}
else {
    $normalizedApplications = @(Get-NormalizedList -Values $Applications)
    $normalizedDataServices = @(Get-NormalizedList -Values $DataServices)
    if ($normalizedApplications.Count -gt 0) {
        $planArguments["Applications"] = @($normalizedApplications)
    }
    if ($normalizedDataServices.Count -gt 0) {
        $planArguments["DataServices"] = @($normalizedDataServices)
    }
    if ($DockerRegistry) {
        $planArguments["DockerRegistry"] = $DockerRegistry
    }
    if ($IncludeJenkins) {
        $planArguments["IncludeJenkins"] = $true
    }
}

$plan = ((& (Join-Path -Path $root -ChildPath "scripts/show-jenkins-job-plan.ps1") @planArguments | Out-String).Trim()) | ConvertFrom-Json

$manifest = [PSCustomObject]@{
    SchemaVersion = "1.0.0"
    Kind = "jenkins-pipeline-template-contract-bundle"
    GeneratedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    RepoRoot = $root
    EnvironmentPresets = @($normalizedPresets)
    Profile = $Profile
    Applications = @(Get-NormalizedList -Values $Applications)
    DataServices = @(Get-NormalizedList -Values $DataServices)
    ValuesFile = $ValuesFile
    HelmConfigFile = $HelmConfigFile
    DockerRegistry = $DockerRegistry
    Version = $Version
    IncludeJenkins = [bool]$IncludeJenkins
    IncludeDeferredComponents = [bool]$IncludeDeferredComponents
    RequireBootstrapSecretsReady = [bool]$RequireBootstrapSecretsReady
    SelectionCount = [int]$plan.SelectionCount
    ServiceJobCount = [int]$plan.ServiceJobCount
    Selections = @($plan.Selections)
    ServiceJobs = @($plan.ServiceJobs)
    Notes = @(
        "This is a public-safe controller-free contract bundle.",
        "It records the generated Jenkins runtime contract and selection inputs.",
        "It does not contain live cluster manifests or prove controller/JCasC readiness."
    )
}

$manifestPath = Join-Path $resolvedOutputPath "bundle-manifest.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestPath -Encoding utf8NoBOM

$readme = @"
# Jenkins Runtime Contract Bundle

This directory was generated by `scripts/invoke-bundle-delivery.ps1`.

It is a controller-free contract bundle for validating Jenkins job inputs,
service catalog metadata, and generated job topology. It does not contain live
cluster manifests and must not be treated as proof that a Jenkins controller,
agents, credentials, registry access, or cluster permissions are ready.

See `bundle-manifest.json` for the selected inputs and generated Jenkins job
plan.
"@
Set-Content -Path (Join-Path $resolvedOutputPath "README.md") -Value $readme -Encoding utf8NoBOM

if (-not $SkipBundleValidation) {
    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        throw "Bundle validation failed because bundle-manifest.json was not written."
    }
}

if ($DeployBundle -and $DeploymentDryRun) {
    Set-Content -Path (Join-Path $resolvedOutputPath "deployment-dry-run.txt") -Value "Dry-run deployment requested; no live cluster action was performed by this public-safe template." -Encoding utf8NoBOM
}

if (-not $SkipArchive) {
    $archiveDirectory = Split-Path -Path $resolvedArchivePath -Parent
    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    if ((Test-Path -Path $resolvedArchivePath -PathType Leaf) -and -not $OverwriteArchive) {
        throw ("ArchivePath already exists. Pass -OverwriteArchive to replace it: {0}" -f $ArchivePath)
    }
    if (Test-Path -Path $resolvedArchivePath -PathType Leaf) {
        Remove-Item -Path $resolvedArchivePath -Force
    }
    Compress-Archive -Path (Join-Path $resolvedOutputPath "*") -DestinationPath $resolvedArchivePath -Force
}

$summary = [PSCustomObject]@{
    Status = "passed"
    OutputPath = $resolvedOutputPath
    ArchivePath = if ($SkipArchive) { "" } else { $resolvedArchivePath }
    Deployment = if ($DeployBundle) { if ($DeploymentDryRun) { "dry-run" } else { "blocked" } } else { "not-requested" }
    Contract = "controller-free Jenkins runtime contract"
}

$summary | ConvertTo-Json -Depth 8
