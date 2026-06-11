function Get-EnvironmentPresetData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [string]$EnvironmentPreset,
        [string]$EnvironmentPresetFile
    )

    if ($EnvironmentPreset -and $EnvironmentPresetFile) {
        throw "Use either -EnvironmentPreset or -EnvironmentPresetFile, but not both."
    }

    if (-not $EnvironmentPreset -and -not $EnvironmentPresetFile) {
        return $null
    }

    $candidatePath = if ($EnvironmentPresetFile) {
        if ([System.IO.Path]::IsPathRooted($EnvironmentPresetFile)) {
            [System.IO.Path]::GetFullPath($EnvironmentPresetFile)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $EnvironmentPresetFile))
        }
    }
    else {
        $presetName = $EnvironmentPreset.Trim()
        if (
            -not $presetName -or
            $presetName -in @(".", "..") -or
            $presetName -ne [System.IO.Path]::GetFileName($presetName) -or
            $presetName -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]*$"
        ) {
            throw ("Environment preset names must be file basenames from config/environments: {0}" -f $EnvironmentPreset)
        }

        $presetDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "config\environments"))
        $resolvedPresetPath = [System.IO.Path]::GetFullPath((Join-Path $presetDirectory ("{0}.psd1" -f $presetName)))
        $presetDirectoryPrefix = $presetDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedPresetPath.StartsWith($presetDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Environment preset must resolve under config/environments: {0}" -f $EnvironmentPreset)
        }

        $resolvedPresetPath
    }

    if (-not (Test-Path -Path $candidatePath -PathType Leaf)) {
        throw ("Environment preset file was not found: {0}" -f $candidatePath)
    }

    $preset = Import-PowerShellDataFile -Path $candidatePath
    if ($null -eq $preset) {
        throw ("Environment preset file was empty: {0}" -f $candidatePath)
    }

    if (-not ($preset -is [hashtable])) {
        throw ("Environment preset must resolve to a PowerShell hashtable: {0}" -f $candidatePath)
    }

    $presetCopy = @{}
    foreach ($key in $preset.Keys) {
        $presetCopy[$key] = $preset[$key]
    }

    $presetCopy["_PresetPath"] = [System.IO.Path]::GetFullPath($candidatePath)
    $presetCopy["_PresetName"] = if ($EnvironmentPreset) { $EnvironmentPreset } else { [System.IO.Path]::GetFileNameWithoutExtension($candidatePath) }
    return $presetCopy
}

function Set-ValueFromEnvironmentPreset {
    param(
        [hashtable]$Preset,
        [hashtable]$BoundParameters,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [ref]$Target,

        [switch]$AsList,
        [switch]$AsSwitch
    )

    if ($null -eq $Preset) {
        return
    }

    if ($BoundParameters.ContainsKey($Key)) {
        return
    }

    if (-not $Preset.ContainsKey($Key)) {
        return
    }

    $value = $Preset[$Key]
    if ($AsList) {
        $Target.Value = @($value)
        return
    }

    if ($AsSwitch) {
        $Target.Value = [bool]$value
        return
    }

    $Target.Value = $value
}

function Get-EnvironmentPresetDisplayText {
    param(
        [hashtable]$Preset
    )

    if ($null -eq $Preset) {
        return ""
    }

    if ($Preset.ContainsKey("_PresetName") -and $Preset.ContainsKey("_PresetPath")) {
        return ("{0} ({1})" -f $Preset["_PresetName"], $Preset["_PresetPath"])
    }

    if ($Preset.ContainsKey("_PresetPath")) {
        return [string]$Preset["_PresetPath"]
    }

    return "custom preset"
}
