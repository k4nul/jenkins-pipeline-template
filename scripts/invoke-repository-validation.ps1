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
    [string]$RenderedPath,
    [switch]$IncludeJenkins,
    [switch]$PrepareHelmRepos,
    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$SkipTemplateValidation,
    [switch]$SkipWorkstationValidation,
    [switch]$SkipPlatformAssetValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "jenkins-job-common.ps1")

function Resolve-RepoInputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw ("{0} must not be empty." -f $Description)
    }

    if ($Path -match "[*?\[\]{}]") {
        throw ("{0} must be a literal path without wildcard or glob characters: {1}" -f $Description, $Path)
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $Path))
    }

    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -ne $resolvedRoot -and -not $resolvedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("{0} must resolve inside the repository: {1}" -f $Description, $Path)
    }

    if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
        throw ("{0} was not found: {1}" -f $Description, $Path)
    }

    return $resolvedPath
}

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path $PSScriptRoot "..")
$valuesPath = Resolve-RepoInputFile -Root $root -Path $ValuesFile -Description "ValuesFile"
$helmConfigPath = Resolve-RepoInputFile -Root $root -Path $HelmConfigFile -Description "HelmConfigFile"
$jobPlanScript = Join-Path $root "scripts/show-jenkins-job-plan.ps1"
$serviceValidationScript = Join-Path $root "scripts/validate-service-pipelines.ps1"
$workstationScript = Join-Path $root "scripts/validate-workstation.ps1"

if (-not $SkipWorkstationValidation) {
    & $workstationScript -ProfileName "repository validation local runtime" -RequiredTools @() -OptionalTools @("git", "kubectl", "helm") -Strict:$Strict | Out-Null
}

if ($PrepareHelmRepos) {
    throw "PrepareHelmRepos is a live Helm action and is not implemented by this public-safe repository validation contract."
}

if ($ValidateCrdBackedResources) {
    throw "ValidateCrdBackedResources requires a cluster with CRDs installed and is outside this controller-free repository validation contract."
}

if (-not $SkipTemplateValidation) {
    $jobPlanArguments = @{
        RepoRoot = $root
        Profile = $Profile
        ValuesFile = $ValuesFile
        Version = $Version
        Format = "json"
    }

    $normalizedPresets = @(Get-NormalizedList -Values $EnvironmentPreset)
    if ($normalizedPresets.Count -gt 0) {
        $jobPlanArguments["EnvironmentPreset"] = @($normalizedPresets)
    }
    else {
        $normalizedApplications = @(Get-NormalizedList -Values $Applications)
        $normalizedDataServices = @(Get-NormalizedList -Values $DataServices)
        if ($normalizedApplications.Count -gt 0) {
            $jobPlanArguments["Applications"] = @($normalizedApplications)
        }
        if ($normalizedDataServices.Count -gt 0) {
            $jobPlanArguments["DataServices"] = @($normalizedDataServices)
        }
        if ($DockerRegistry) {
            $jobPlanArguments["DockerRegistry"] = $DockerRegistry
        }
        if ($IncludeJenkins) {
            $jobPlanArguments["IncludeJenkins"] = $true
        }
    }

    $planJson = (& $jobPlanScript @jobPlanArguments | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($planJson)) {
        throw "Jenkins job plan returned empty output."
    }
    $plan = $planJson | ConvertFrom-Json
}
else {
    $plan = $null
}

& $serviceValidationScript -RepoRoot $root 6>$null | Out-Null

if ($RenderedPath) {
    $resolvedRenderedPath = Resolve-RepoOutputPath -RepoRoot $root -Path $RenderedPath
    if (-not (Test-Path -Path $resolvedRenderedPath -PathType Container)) {
        throw ("RenderedPath does not exist or is not a directory: {0}" -f $RenderedPath)
    }

    $manifestPath = Join-Path $resolvedRenderedPath "bundle-manifest.json"
    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        throw ("RenderedPath must contain a bundle-manifest.json produced by invoke-bundle-delivery.ps1: {0}" -f $RenderedPath)
    }
}
elseif (-not $SkipPlatformAssetValidation) {
    Write-Information -MessageData "No RenderedPath supplied; repository validation completed the controller-free contract checks only." -InformationAction Continue
}

if ($RequireBootstrapSecretsReady) {
    Write-Information -MessageData "No rendered bootstrap secret templates were supplied; bootstrap secret readiness is satisfied only for the controller-free contract checks." -InformationAction Continue
}

$summary = [PSCustomObject]@{
    Status = "passed"
    RepoRoot = $root
    EnvironmentPresets = @(Get-NormalizedList -Values $EnvironmentPreset)
    Profile = $Profile
    Applications = @(Get-NormalizedList -Values $Applications)
    DataServices = @(Get-NormalizedList -Values $DataServices)
    ValuesFile = $valuesPath
    HelmConfigFile = $helmConfigPath
    Version = $Version
    SelectionCount = if ($null -ne $plan) { [int]$plan.SelectionCount } else { 0 }
    ServiceJobCount = if ($null -ne $plan) { [int]$plan.ServiceJobCount } else { 0 }
    Contract = "controller-free Jenkins runtime contract"
}

$summary | ConvertTo-Json -Depth 8
