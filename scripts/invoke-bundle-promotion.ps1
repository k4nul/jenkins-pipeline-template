param(
    [string]$RepoRoot,
    [string[]]$EnvironmentPreset,
    [string]$ArchivePath = "out/ci/web-platform.zip",
    [string]$ExtractPath = "out/promotion/web-platform",
    [switch]$CleanExtractPath,
    [switch]$PrepareHelmRepos,
    [switch]$IncludeDeferredComponents,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$RequireBootstrapStatus,
    [switch]$SkipBundleValidation,
    [switch]$DeployBundle,
    [switch]$DeploymentDryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "jenkins-job-common.ps1")

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path $PSScriptRoot "..")
$resolvedArchivePath = Resolve-RepoOutputPath -RepoRoot $root -Path $ArchivePath
$resolvedExtractPath = Resolve-RepoOutputPath -RepoRoot $root -Path $ExtractPath

if (-not (Test-Path -Path $resolvedArchivePath -PathType Leaf)) {
    throw ("ArchivePath was not found: {0}" -f $ArchivePath)
}

if ($DeployBundle -and -not $DeploymentDryRun) {
    throw "Non-dry-run bundle promotion deployment is not implemented in this public-safe Jenkins template. Keep DeploymentDryRun enabled or provide a downstream deployment implementation."
}

if ($PrepareHelmRepos) {
    throw "PrepareHelmRepos is a live Helm action and is not implemented by this public-safe bundle promotion contract."
}

if ($RequireBootstrapStatus) {
    throw "RequireBootstrapStatus needs a live cluster and is outside this controller-free bundle promotion contract."
}

if ((Test-Path -Path $resolvedExtractPath) -and $CleanExtractPath) {
    Remove-Item -Path $resolvedExtractPath -Recurse -Force
}

if ((Test-Path -Path $resolvedExtractPath) -and -not $CleanExtractPath) {
    throw ("ExtractPath already exists. Pass -CleanExtractPath to replace it: {0}" -f $ExtractPath)
}

New-Item -ItemType Directory -Path $resolvedExtractPath -Force | Out-Null
Expand-Archive -Path $resolvedArchivePath -DestinationPath $resolvedExtractPath -Force

$manifestPath = Join-Path $resolvedExtractPath "bundle-manifest.json"
if (-not $SkipBundleValidation) {
    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        throw "Promoted bundle validation failed because bundle-manifest.json was not found after extraction."
    }
}

if ($DeployBundle -and $DeploymentDryRun) {
    Set-Content -Path (Join-Path $resolvedExtractPath "promotion-dry-run.txt") -Value "Dry-run promotion deployment requested; no live cluster action was performed by this public-safe template." -Encoding utf8NoBOM
}

if ($RequireBootstrapSecretsReady) {
    Write-Information -MessageData "No rendered bootstrap secret templates were supplied; bootstrap secret readiness is satisfied only for the controller-free promotion contract." -InformationAction Continue
}

$summary = [PSCustomObject]@{
    Status = "passed"
    EnvironmentPresets = @(Get-NormalizedList -Values $EnvironmentPreset)
    ArchivePath = $resolvedArchivePath
    ExtractPath = $resolvedExtractPath
    Deployment = if ($DeployBundle) { if ($DeploymentDryRun) { "dry-run" } else { "blocked" } } else { "not-requested" }
    IncludeDeferredComponents = [bool]$IncludeDeferredComponents
    Contract = "controller-free Jenkins runtime contract"
}

$summary | ConvertTo-Json -Depth 8
