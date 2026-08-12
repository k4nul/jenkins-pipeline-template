param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publicPresetTests = Join-Path -Path $PSScriptRoot -ChildPath "../tests/jenkins-job-dsl.public-presets.ps1"

if (-not (Test-Path -Path $publicPresetTests -PathType Leaf)) {
    throw "Pipeline contract test suite was not found: $publicPresetTests"
}

& $publicPresetTests -RepoRoot $RepoRoot

Write-Output "Controller-free pipeline contract tests passed."
