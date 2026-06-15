param(
    [string]$ProfileName = "Jenkins agent",
    [string[]]$RequiredTools = @(),
    [string[]]$OptionalTools = @(),
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UniqueToolList {
    param(
        [string[]]$Values
    )

    return @(
        @($Values) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Test-ToolOnPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

$required = @(Get-UniqueToolList -Values $RequiredTools)
$optional = @(Get-UniqueToolList -Values $OptionalTools)
$missingRequired = New-Object System.Collections.Generic.List[string]
$missingOptional = New-Object System.Collections.Generic.List[string]

foreach ($tool in $required) {
    if (-not (Test-ToolOnPath -Name $tool)) {
        $missingRequired.Add($tool) | Out-Null
    }
}

foreach ($tool in $optional) {
    if (-not (Test-ToolOnPath -Name $tool)) {
        $missingOptional.Add($tool) | Out-Null
    }
}

$summary = [PSCustomObject]@{
    ProfileName = $ProfileName
    RequiredTools = @($required)
    OptionalTools = @($optional)
    MissingRequiredTools = @($missingRequired.ToArray())
    MissingOptionalTools = @($missingOptional.ToArray())
    Strict = [bool]$Strict
    Status = if ($missingRequired.Count -eq 0) { "passed" } else { "failed" }
}

if ($missingRequired.Count -gt 0) {
    $message = "Workstation validation failed for {0}; missing required tools: {1}" -f $ProfileName, ($missingRequired.ToArray() -join ", ")
    if ($Strict) {
        throw $message
    }

    Write-Warning $message
}

if ($missingOptional.Count -gt 0) {
    Write-Warning ("Optional tools were not found for {0}: {1}" -f $ProfileName, ($missingOptional.ToArray() -join ", "))
}

Write-Output $summary
