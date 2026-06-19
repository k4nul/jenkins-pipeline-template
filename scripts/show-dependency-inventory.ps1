param(
    [string]$RepoRoot,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-job-common.ps1")

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathValue = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar

    if ($pathValue.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathValue.Substring($rootPrefix.Length).Replace([System.IO.Path]::DirectorySeparatorChar, "/")
    }

    return $pathValue
}

function Get-ImageTagInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageReference
    )

    $withoutDigest = ($ImageReference -split "@", 2)[0]
    $lastSlash = $withoutDigest.LastIndexOf("/")
    $lastColon = $withoutDigest.LastIndexOf(":")
    $tag = ""

    if ($lastColon -gt $lastSlash) {
        $tag = $withoutDigest.Substring($lastColon + 1)
    }

    $isDigestPinned = $ImageReference -match "@sha256:[A-Fa-f0-9]{64}"
    $usesFloatingTag = (-not $isDigestPinned) -and ($tag -in @("", "latest", "lts", "stable"))

    return [PSCustomObject]@{
        Tag = $tag
        IsDigestPinned = [bool]$isDigestPinned
        UsesFloatingTag = [bool]$usesFloatingTag
    }
}

function Find-PackageManagerManifests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $manifestNames = @(
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "requirements.txt",
        "requirements-dev.txt",
        "pyproject.toml",
        "Pipfile",
        "Pipfile.lock",
        "go.mod",
        "go.sum",
        "Cargo.toml",
        "Cargo.lock",
        "global.json"
    )

    return @(
        Get-ChildItem -Path $Root -Recurse -File -Force |
            Where-Object {
                $relativePath = Get-RepoRelativePath -Root $Root -Path $_.FullName
                $parts = @($relativePath -split "/")
                $parts -notcontains ".git" -and
                    $parts -notcontains "out" -and
                    $manifestNames -contains $_.Name
            } |
            Sort-Object FullName |
            ForEach-Object {
                [PSCustomObject]@{
                    Path = Get-RepoRelativePath -Root $Root -Path $_.FullName
                    Name = $_.Name
                }
            }
    )
}

function Find-ControllerImages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $k8sRoot = Join-Path $Root "k8s"
    if (-not (Test-Path -Path $k8sRoot -PathType Container)) {
        return @()
    }

    $images = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -Path $k8sRoot -Recurse -File -Include "*.yaml", "*.yml" | Sort-Object FullName)) {
        $lines = @(Get-Content -Path $file.FullName)
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match "^\s*image:\s*['""]?([^'""]+)['""]?\s*$") {
                $imageReference = $Matches[1].Trim()
                $tagInfo = Get-ImageTagInfo -ImageReference $imageReference
                $images.Add([PSCustomObject]@{
                    SourcePath = Get-RepoRelativePath -Root $Root -Path $file.FullName
                    LineNumber = $index + 1
                    ImageReference = $imageReference
                    Tag = $tagInfo.Tag
                    IsDigestPinned = $tagInfo.IsDigestPinned
                    UsesFloatingTag = $tagInfo.UsesFloatingTag
                }) | Out-Null
            }
        }
    }

    return @($images.ToArray())
}

function New-DependencyInventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $catalog = Import-ServicePipelineCatalog -RepoRoot $Root
    $services = @(Get-ServicePipelineCatalogServices -Catalog $catalog)
    $serviceImages = @(
        $services |
            ForEach-Object {
                $tagInfo = Get-ImageTagInfo -ImageReference ([string]$_.ImageName)
                [PSCustomObject]@{
                    Name = [string]$_.Name
                    Category = [string]$_.Category
                    ImageReference = [string]$_.ImageName
                    Tag = $tagInfo.Tag
                    IsDigestPinned = $tagInfo.IsDigestPinned
                    UsesFloatingTag = $tagInfo.UsesFloatingTag
                    HasJenkinsfile = [bool]$_.HasJenkinsfile
                }
            }
    )

    $packageManagerManifests = @(Find-PackageManagerManifests -Root $Root)
    $controllerImages = @(Find-ControllerImages -Root $Root)
    $floatingControllerImages = @($controllerImages | Where-Object { [bool]$_.UsesFloatingTag })

    $riskIndicators = New-Object System.Collections.Generic.List[string]
    if ($packageManagerManifests.Count -eq 0) {
        $riskIndicators.Add("No package-manager manifests or lockfiles were found; dependency health is catalog and runtime-contract driven.") | Out-Null
    }

    if ($floatingControllerImages.Count -gt 0) {
        $riskIndicators.Add("One or more controller image references use a floating tag and need release-note review before production use.") | Out-Null
    }

    if (@($serviceImages | Where-Object { -not [bool]$_.IsDigestPinned }).Count -gt 0) {
        $riskIndicators.Add("Public service image references are tag-based; refresh them only as a release-note-reviewed catalog batch.") | Out-Null
    }

    return [PSCustomObject]@{
        Status = "passed"
        PackageManagerManifests = @($packageManagerManifests)
        ServiceImages = @($serviceImages)
        ControllerImages = @($controllerImages)
        Toolchain = [PSCustomObject]@{
            PowerShellMinimum = "7+"
            PhaseValidation = "sh scripts/run-phase-validation.sh"
        }
        RiskIndicators = @($riskIndicators.ToArray())
    }
}

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path -Path $PSScriptRoot -ChildPath "..")
$inventory = New-DependencyInventory -Root $root

switch ($Format) {
    "json" {
        $document = $inventory | ConvertTo-Json -Depth 8
    }
    "markdown" {
        $lines = @(
            "# Dependency Inventory",
            "",
            "## Summary",
            "",
            ("- Status: " + $inventory.Status),
            ("- Package manager manifests: " + [string]@($inventory.PackageManagerManifests).Count),
            ("- Public service images: " + [string]@($inventory.ServiceImages).Count),
            ("- Controller image references: " + [string]@($inventory.ControllerImages).Count),
            "",
            "## Public Service Images",
            "",
            "| Service | Category | Image | Tag | Floating tag | Digest pinned | Jenkinsfile-backed |",
            "| --- | --- | --- | --- | --- | --- | --- |"
        )

        foreach ($image in @($inventory.ServiceImages)) {
            $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $image.Name, $image.Category, $image.ImageReference, $(if ($image.Tag) { $image.Tag } else { "none" }), $image.UsesFloatingTag, $image.IsDigestPinned, $image.HasJenkinsfile)
        }

        $lines += @(
            "",
            "## Controller Images",
            "",
            "| Source | Image | Tag | Floating tag | Digest pinned |",
            "| --- | --- | --- | --- | --- |"
        )

        foreach ($image in @($inventory.ControllerImages)) {
            $lines += ("| {0}:{1} | {2} | {3} | {4} | {5} |" -f $image.SourcePath, $image.LineNumber, $image.ImageReference, $(if ($image.Tag) { $image.Tag } else { "none" }), $image.UsesFloatingTag, $image.IsDigestPinned)
        }

        $lines += @(
            "",
            "## Risk Indicators",
            ""
        )

        foreach ($indicator in @($inventory.RiskIndicators)) {
            $lines += ("- " + $indicator)
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Dependency Inventory",
            "====================",
            ("Status: " + $inventory.Status),
            ("Package manager manifests: " + [string]@($inventory.PackageManagerManifests).Count),
            ("Public service images: " + [string]@($inventory.ServiceImages).Count),
            ("Controller image references: " + [string]@($inventory.ControllerImages).Count),
            "",
            "Public service images:"
        )

        foreach ($image in @($inventory.ServiceImages)) {
            $lines += ("  {0}: {1} (tag: {2}, floating: {3}, digest pinned: {4}, Jenkinsfile-backed: {5})" -f $image.Name, $image.ImageReference, $(if ($image.Tag) { $image.Tag } else { "none" }), $image.UsesFloatingTag, $image.IsDigestPinned, $image.HasJenkinsfile)
        }

        $lines += ""
        $lines += "Controller images:"
        foreach ($image in @($inventory.ControllerImages)) {
            $lines += ("  {0}:{1}: {2} (tag: {3}, floating: {4}, digest pinned: {5})" -f $image.SourcePath, $image.LineNumber, $image.ImageReference, $(if ($image.Tag) { $image.Tag } else { "none" }), $image.UsesFloatingTag, $image.IsDigestPinned)
        }

        $lines += ""
        $lines += "Risk indicators:"
        foreach ($indicator in @($inventory.RiskIndicators)) {
            $lines += ("  - " + $indicator)
        }

        $document = $lines -join [Environment]::NewLine
    }
}

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    Write-RepoDocument -RepoRoot $root -Path $OutputPath -Document $document -Description "dependency inventory"
}
else {
    Write-Output $document
}
