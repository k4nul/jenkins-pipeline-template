# Shared helpers for Jenkins job planning and Job DSL export scripts.

function Get-NormalizedList {
    param(
        [object[]]$Values
    )

    return @(
        @($Values) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_ -split "\s*,\s*" } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    $normalized = @(Get-NormalizedList -Values $Values)
    if ($normalized.Count -gt 0) {
        return ($normalized -join ", ")
    }

    return $Empty
}

function Resolve-RepoRoot {
    param(
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot
    )

    if (-not $RepoRoot) {
        $RepoRoot = $DefaultRoot
    }

    return (Resolve-Path -Path $RepoRoot).Path
}

function Get-ServicePipelineCatalogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return (Join-Path $RepoRoot "config\service-pipelines.psd1")
}

function Import-ServicePipelineCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return (Import-PowerShellDataFile -Path (Get-ServicePipelineCatalogPath -RepoRoot $RepoRoot))
}

function Get-ServicePipelineCatalogServices {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Catalog
    )

    $seenNames = @{}
    $services = @()
    foreach ($service in @($Catalog.Services)) {
        $serviceName = Assert-ServiceCatalogNameSafety -Name ([string]$service.Name)
        if ($seenNames.ContainsKey($serviceName)) {
            throw ("Duplicate service catalog entry name is not allowed: {0}" -f $serviceName)
        }

        $seenNames[$serviceName] = $true
        $services += $service
    }

    return @($services | Sort-Object { $_.Name })
}

function Get-ServicePipelineCatalogIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Services
    )

    $index = [ordered]@{}
    foreach ($service in @($Services)) {
        $serviceName = Assert-ServiceCatalogNameSafety -Name ([string]$service.Name)
        if ($index.Contains($serviceName)) {
            throw ("Duplicate service catalog entry name is not allowed: {0}" -f $serviceName)
        }

        $index[$serviceName] = $service
    }

    return $index
}

function Assert-ServiceCatalogNameSafety {
    param(
        [AllowEmptyString()]
        [string]$Name
    )

    $nameText = ([string]$Name).Trim()
    if (-not $nameText) {
        throw "Service catalog entry name must not be empty."
    }

    if (
        $nameText -ne [string]$Name -or
        $nameText -in @(".", "..") -or
        $nameText -match "[/\\]" -or
        $nameText -match "[\x00-\x1F\x7F]" -or
        $nameText -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]*$"
    ) {
        throw ("Service catalog entry name is not allowed: {0}" -f $Name)
    }

    return $nameText
}

function Get-ServicePipelineCommonEnvironmentVariables {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Services
    )

    return @(
        $Services |
            ForEach-Object { @($_.OptionalEnvVars) } |
            Sort-Object -Unique
    )
}

function Resolve-RepoOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -match "[*?\[\]{}]") {
        throw ("OutputPath must be a literal path without wildcard or glob characters: {0}" -f $Path)
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot "out"))
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $Path))
    }

    $outputRootPrefix = $outputRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -ne $outputRoot -and -not $resolvedPath.StartsWith($outputRootPrefix, [System.StringComparison]::Ordinal)) {
        throw ("OutputPath must resolve under the repository out directory: {0}" -f $Path)
    }

    return $resolvedPath
}

function Assert-ZipArchiveEntrySafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $resolvedDestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    $destinationPathPrefix = $resolvedDestinationPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $archive = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
        foreach ($entry in @($archive.Entries)) {
            $entryName = [string]$entry.FullName
            $normalizedEntryName = $entryName.Replace("\", "/").TrimEnd("/")

            if ([string]::IsNullOrWhiteSpace($normalizedEntryName)) {
                throw ("Archive entry path must not be empty: {0}" -f $ArchivePath)
            }

            if ($normalizedEntryName -match "[\x00-\x1F\x7F*?\[\]{}:]") {
                throw ("Archive entry path contains unsupported characters: {0}" -f $entryName)
            }

            if ($normalizedEntryName.StartsWith("/") -or $normalizedEntryName -match "^[A-Za-z]:/") {
                throw ("Archive entry path must be relative: {0}" -f $entryName)
            }

            $segments = @($normalizedEntryName -split "/")
            foreach ($segment in $segments) {
                if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @(".", "..")) {
                    throw ("Archive entry path must not contain empty, current-directory, or parent-directory segments: {0}" -f $entryName)
                }
            }

            $resolvedEntryPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedDestinationPath $normalizedEntryName))
            if ($resolvedEntryPath -ne $resolvedDestinationPath -and -not $resolvedEntryPath.StartsWith($destinationPathPrefix, [System.StringComparison]::Ordinal)) {
                throw ("Archive entry path must extract inside the promotion directory: {0}" -f $entryName)
            }
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Write-RepoDocument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowEmptyString()]
        [string]$Document,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $resolvedOutputPath = Resolve-RepoOutputPath -RepoRoot $RepoRoot -Path $Path
    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    if (Test-Path -Path $resolvedOutputPath -PathType Leaf) {
        $existingDocument = Get-Content -Path $resolvedOutputPath -Raw
        if ($existingDocument -eq $Document) {
            Write-Information -MessageData ("{0} is already up to date at {1}" -f $Description, $resolvedOutputPath) -InformationAction Continue
            return
        }
    }

    Set-Content -Path $resolvedOutputPath -Value $Document -NoNewline
    Write-Information -MessageData ("Wrote {0} to {1}" -f $Description, $resolvedOutputPath) -InformationAction Continue
}

function Add-JobPlanListArgument {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object[]]$Value
    )

    $normalized = @(Get-NormalizedList -Values $Value)
    if ($normalized.Count -gt 0) {
        $Arguments[$Name] = @($normalized)
    }
}

function Add-JobPlanScalarArgument {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments,

        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object]$Value
    )

    if ($BoundParameters.ContainsKey($Name)) {
        if ($Value) {
            $Arguments[$Name] = $Value
        }
    }
}

function New-JenkinsJobPlanArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [string]$JobRoot,
        [string]$ServiceJobRoot,
        [string]$Format = "json",
        [string[]]$EnvironmentPreset,
        [string]$SelectionName,
        [string]$Profile,
        [string[]]$Applications,
        [string[]]$DataServices,
        [string]$ValuesFile,
        [string]$DockerRegistry,
        [string]$Version,
        [string]$BundleOutputPath,
        [string]$ArchivePath,
        [string]$PromotionExtractPath,
        [switch]$IncludeJenkins,
        [switch]$SkipServiceJobs,
        [hashtable]$BoundParameters = @{}
    )

    $arguments = @{
        RepoRoot = $RepoRoot
        Format = $Format
    }

    if ($BoundParameters.ContainsKey("JobRoot") -or $JobRoot) {
        $arguments["JobRoot"] = $JobRoot
    }
    if ($BoundParameters.ContainsKey("ServiceJobRoot") -or $ServiceJobRoot) {
        $arguments["ServiceJobRoot"] = $ServiceJobRoot
    }

    Add-JobPlanListArgument -Arguments $arguments -Name "EnvironmentPreset" -Value $EnvironmentPreset
    Add-JobPlanListArgument -Arguments $arguments -Name "Applications" -Value $Applications
    Add-JobPlanListArgument -Arguments $arguments -Name "DataServices" -Value $DataServices

    $scalarArguments = @{
        SelectionName = $SelectionName
        Profile = $Profile
        ValuesFile = $ValuesFile
        DockerRegistry = $DockerRegistry
        Version = $Version
        BundleOutputPath = $BundleOutputPath
        ArchivePath = $ArchivePath
        PromotionExtractPath = $PromotionExtractPath
    }

    foreach ($boundName in @($scalarArguments.Keys)) {
        Add-JobPlanScalarArgument `
            -Arguments $arguments `
            -BoundParameters $BoundParameters `
            -Name $boundName `
            -Value $scalarArguments[$boundName]
    }

    if ($IncludeJenkins) {
        $arguments["IncludeJenkins"] = $true
    }

    if ($SkipServiceJobs) {
        $arguments["SkipServiceJobs"] = $true
    }

    return $arguments
}

function Join-JobPath {
    param(
        [string[]]$Segments
    )

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($Segments)) {
        foreach ($part in @(([string]$segment -split "[\\/]+"))) {
            $trimmed = $part.Trim()
            if ($trimmed) {
                if (
                    $trimmed -in @(".", "..") -or
                    $trimmed -match "[\x00-\x1F\x7F]" -or
                    $trimmed -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]*$"
                ) {
                    throw ("Jenkins job path segment is not allowed: {0}" -f $trimmed)
                }

                $parts.Add($trimmed) | Out-Null
            }
        }
    }

    if ($parts.Count -eq 0) {
        throw "Jenkins job path must include at least one safe segment."
    }

    return ($parts.ToArray() -join "/")
}

function Get-FolderPathsFromJobPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobPath
    )

    $segments = @(
        $JobPath -split "[/\\]+" |
            Where-Object { $_ }
    )

    $folders = New-Object System.Collections.Generic.List[string]
    if ($segments.Count -lt 2) {
        return @()
    }

    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        $folders.Add(($segments[0..$index] -join "/")) | Out-Null
    }

    return @($folders.ToArray())
}
