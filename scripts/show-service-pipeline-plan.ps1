param(
    [string]$RepoRoot,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-job-common.ps1")

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path -Path $PSScriptRoot -ChildPath "..")
$catalog = Import-ServicePipelineCatalog -RepoRoot $root
$services = @(Get-ServicePipelineCatalogServices -Catalog $catalog)
$commonEnvVars = @(Get-ServicePipelineCommonEnvironmentVariables -Services $services)

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            CommonEnvironmentVariables = @($commonEnvVars)
            Services = @($services)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Pipeline Plan",
            "",
            "## Summary",
            "",
            ("- Services: " + [string]$services.Count),
            ("- Shared Jenkins variables: " + $(if ($commonEnvVars.Count -gt 0) { $commonEnvVars -join ", " } else { "none" })),
            ""
        )

        $lines += "## Service Matrix"
        $lines += ""
        $lines += "| Service | Category | Image | Build Tag | Jenkinsfile | Notes |"
        $lines += "| --- | --- | --- | --- | --- | --- |"
        foreach ($service in $services) {
            $jenkinsfileState = if ([bool]$service.HasJenkinsfile) { "yes" } else { "no" }
            $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $service.Name, $service.Category, $service.ImageName, $service.BuildTagStrategy, $jenkinsfileState, $service.Notes)
        }

        $lines += ""
        $lines += "## Service Details"
        $lines += ""

        foreach ($service in $services) {
            $lines += ("### " + $service.Name)
            $lines += ""
            $lines += ("- Category: " + $service.Category)
            $lines += ("- Public image: " + $service.ImageName)
            $lines += ("- Build tag strategy: " + $service.BuildTagStrategy)
            $lines += ("- Compose update: " + $service.ComposeUpdate)
            $lines += ("- Jenkinsfile present: " + [string]([bool]$service.HasJenkinsfile))
            $lines += ("- Required files: " + (@($service.RequiredFiles) -join ", "))
            $lines += ("- Notes: " + $service.Notes)
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Pipeline Plan",
            "=====================",
            ("Services: " + [string]$services.Count),
            ""
        )

        foreach ($service in $services) {
            $lines += ($service.Name + " [" + $service.Category + "]")
            $lines += ("  Public image: " + $service.ImageName)
            $lines += ("  Build tag strategy: " + $service.BuildTagStrategy)
            $lines += ("  Compose update: " + $service.ComposeUpdate)
            $lines += ("  Jenkinsfile present: " + [string]([bool]$service.HasJenkinsfile))
            $lines += ("  Required files: " + (@($service.RequiredFiles) -join ", "))
            $lines += ("  Notes: " + $service.Notes)
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
}

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    Write-RepoDocument -RepoRoot $root -Path $OutputPath -Document $document -Description "service pipeline plan"
}
else {
    Write-Output $document
}
