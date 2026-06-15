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
    if ($resolvedPath -ne $outputRoot -and -not $resolvedPath.StartsWith($outputRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("OutputPath must resolve under the repository out directory: {0}" -f $Path)
    }

    return $resolvedPath
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

    Set-Content -Path $resolvedOutputPath -Value $Document -NoNewline
    Write-Information -MessageData ("Wrote {0} to {1}" -f $Description, $resolvedOutputPath) -InformationAction Continue
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
