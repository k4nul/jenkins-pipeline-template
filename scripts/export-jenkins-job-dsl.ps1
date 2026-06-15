param(
    [string]$RepoRoot,
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
    [string]$JobRoot = "platform",
    [string]$ServiceJobRoot = "services",
    [switch]$IncludeJenkins,
    [switch]$SkipServiceJobs,
    [string]$RepoUrl = "REPLACE_WITH_REPOSITORY_URL",
    [string]$BranchSpec = "REPLACE_WITH_BRANCH_SPEC",
    [string]$ScmCredentialsId,
    [bool]$UseLightweightCheckout = $true,
    [string]$OutputPath = "out\jenkins\seed-job-dsl.groovy"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "jenkins-job-common.ps1")

function ConvertTo-GroovyString {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    $escaped = $Value.Replace("\", "\\").Replace("'", "\'").Replace("`r", "").Replace("`n", "\n")
    return ("'{0}'" -f $escaped)
}

function ConvertTo-RelativeScmPath {
    param(
        [string]$Path
    )

    return ([string]$Path).Replace("\", "/")
}

function Add-UniqueFolderDescription {
    param(
        [hashtable]$Map,
        [string]$Path,
        [string]$Description,
        [switch]$Replace
    )

    if (-not $Path) {
        return
    }

    if ($Replace -or -not $Map.ContainsKey($Path)) {
        $Map[$Path] = $Description
    }
}

function Get-BundlePipelineJobDescriptionLines {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Selection,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Job
    )

    $descriptionLines = @(
        "Generated bundle pipeline job.",
        ("Selection: {0}" -f $Selection.Name),
        ("Profile: {0}" -f $Selection.Profile),
        ("Applications: {0}" -f (Get-TextList -Values $Selection.Applications)),
        ("Data services: {0}" -f (Get-TextList -Values $Selection.DataServices)),
        ("Purpose: {0}" -f $Job.Purpose),
        ("Recommended trigger: {0}" -f $Job.RecommendedTrigger),
        ("Upstream dependencies: {0}" -f (Get-TextList -Values $Job.UpstreamDependencies))
    )

    if ($Job.ArtifactOutputs) {
        $descriptionLines += ("Artifact outputs: {0}" -f (Get-TextList -Values $Job.ArtifactOutputs))
    }

    if ($Job.KeyParameters) {
        $descriptionLines += "Key parameters:"
        foreach ($keyParameter in @($Job.KeyParameters)) {
            $descriptionLines += ("- {0}" -f $keyParameter)
        }
    }

    $descriptionLines += ("Local command: {0}" -f $Job.LocalCommand)

    return @($descriptionLines)
}

function Get-ServicePipelineJobDescriptionLines {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ServiceJob
    )

    $descriptionLines = @(
        "Generated service image pipeline job.",
        ("Service: {0}" -f $ServiceJob.Name),
        ("Category: {0}" -f $ServiceJob.Category),
        ("Image name: {0}" -f $ServiceJob.ImageName),
        ("Build tag strategy: {0}" -f $ServiceJob.BuildTagStrategy),
        ("Compose update behavior: {0}" -f $ServiceJob.ComposeUpdate),
        ("Used by selections: {0}" -f (Get-TextList -Values $ServiceJob.UsedBySelections)),
        ("Required environment variables: {0}" -f (Get-TextList -Values $ServiceJob.RequiredEnvironmentVariables)),
        ("Optional environment variables: {0}" -f (Get-TextList -Values $ServiceJob.OptionalEnvironmentVariables)),
        ("Recommended trigger: {0}" -f $ServiceJob.RecommendedTrigger),
        ("Notes: {0}" -f $ServiceJob.Notes)
    )

    if ($ServiceJob.UpstreamArtifactInputs) {
        $descriptionLines += "Upstream artifact inputs:"
        foreach ($artifactInput in @($ServiceJob.UpstreamArtifactInputs)) {
            $descriptionLines += ("- {0}" -f $artifactInput)
        }
    }

    return @($descriptionLines)
}

function Get-GeneratedPipelineJobDslLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Jenkinsfile,

        [Parameter(Mandatory = $true)]
        [string[]]$DescriptionLines
    )

    return @(
        ("pipelineJob({0}) {{" -f (ConvertTo-GroovyString -Value $Path)),
        ("    configureGeneratedPipelineJob(delegate, {0}, {1})" -f `
            (ConvertTo-GroovyString -Value (ConvertTo-RelativeScmPath -Path $Jenkinsfile)), `
            (ConvertTo-GroovyString -Value ($DescriptionLines -join "`n"))),
        "}",
        ""
    )
}

$root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot (Join-Path $PSScriptRoot "..")
$jobPlanScript = Join-Path $root "scripts\show-jenkins-job-plan.ps1"
$repoUrlForDsl = if ([string]::IsNullOrWhiteSpace($RepoUrl)) { "REPLACE_WITH_REPOSITORY_URL" } else { $RepoUrl.Trim() }
$branchSpecForDsl = if ([string]::IsNullOrWhiteSpace($BranchSpec)) { "REPLACE_WITH_BRANCH_SPEC" } else { $BranchSpec.Trim() }
$scmCredentialsIdForDsl = if ([string]::IsNullOrWhiteSpace($ScmCredentialsId)) { "" } else { $ScmCredentialsId.Trim() }

$jobPlanArguments = @{
    RepoRoot = $root
    JobRoot = $JobRoot
    ServiceJobRoot = $ServiceJobRoot
    Format = "json"
}

if (@(Get-NormalizedList -Values $EnvironmentPreset).Count -gt 0) {
    $jobPlanArguments["EnvironmentPreset"] = @(Get-NormalizedList -Values $EnvironmentPreset)
}

if ($PSBoundParameters.ContainsKey("SelectionName") -and $SelectionName) {
    $jobPlanArguments["SelectionName"] = $SelectionName
}

if ($PSBoundParameters.ContainsKey("Profile") -and $Profile) {
    $jobPlanArguments["Profile"] = $Profile
}

if (@(Get-NormalizedList -Values $Applications).Count -gt 0) {
    $jobPlanArguments["Applications"] = @(Get-NormalizedList -Values $Applications)
}

if (@(Get-NormalizedList -Values $DataServices).Count -gt 0) {
    $jobPlanArguments["DataServices"] = @(Get-NormalizedList -Values $DataServices)
}

foreach ($optionalName in @("ValuesFile", "DockerRegistry", "Version", "BundleOutputPath", "ArchivePath", "PromotionExtractPath")) {
    if ($PSBoundParameters.ContainsKey($optionalName) -and (Get-Variable -Name $optionalName -ValueOnly)) {
        $jobPlanArguments[$optionalName] = Get-Variable -Name $optionalName -ValueOnly
    }
}

if ($IncludeJenkins) {
    $jobPlanArguments["IncludeJenkins"] = $true
}

if ($SkipServiceJobs) {
    $jobPlanArguments["SkipServiceJobs"] = $true
}

$jobPlanJson = (& $jobPlanScript @jobPlanArguments | Out-String).Trim()
if (-not $jobPlanJson) {
    throw "Jenkins job plan script did not return any JSON output."
}

$jobPlan = $jobPlanJson | ConvertFrom-Json
$selections = @($jobPlan.Selections)
$serviceJobs = @($jobPlan.ServiceJobs)

$folderDescriptions = @{}
$bundleRootPath = Join-JobPath -Segments @($JobRoot)
$serviceRootPath = Join-JobPath -Segments @($ServiceJobRoot)

foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath ($bundleRootPath + "/placeholder"))) {
    Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder for reusable bundle validation, delivery, and promotion jobs."
}

foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath ($serviceRootPath + "/placeholder"))) {
    Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder for reusable service image build jobs."
}

foreach ($selection in $selections) {
    foreach ($job in @($selection.PipelineJobs)) {
        foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath $job.Path)) {
            Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder created from the reusable bundle job topology."
        }
    }

    Add-UniqueFolderDescription `
        -Map $folderDescriptions `
        -Path ([string]$selection.BundleFolderPath) `
        -Description ("Generated bundle job folder for selection '{0}' using profile '{1}'." -f $selection.Name, $selection.Profile) `
        -Replace
}

foreach ($serviceJob in $serviceJobs) {
    foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath $serviceJob.Path)) {
        Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder that groups service image pipeline jobs used by the selected bundle plans."
    }
}

$sortedFolderPaths = @(
    $folderDescriptions.Keys |
        Sort-Object @{ Expression = { ($_ -split "/").Count } }, @{ Expression = { $_ } }
)

$lines = @(
    "// Generated by scripts/export-jenkins-job-dsl.ps1.",
    "// SCM defaults are public-safe placeholders unless -RepoUrl and -BranchSpec are supplied.",
    ("// Selection count: {0}" -f $selections.Count),
    ("// Service job count: {0}" -f $serviceJobs.Count),
    "",
    ("String repoUrl = {0}" -f (ConvertTo-GroovyString -Value $repoUrlForDsl)),
    ("String branchSpec = {0}" -f (ConvertTo-GroovyString -Value $branchSpecForDsl)),
    ("String scmCredentialsId = {0}" -f (ConvertTo-GroovyString -Value $scmCredentialsIdForDsl)),
    ("boolean useLightweightCheckout = {0}" -f $UseLightweightCheckout.ToString().ToLowerInvariant()),
    "",
    "def configureGeneratedPipelineJob = { jobContext, String scriptPath, String descriptionText ->",
    "    jobContext.description(descriptionText)",
    "    jobContext.logRotator {",
    "        numToKeep(30)",
    "    }",
    "    jobContext.definition {",
    "        cpsScm {",
    "            lightweight(useLightweightCheckout)",
    "            scm {",
    "                git {",
    "                    remote {",
    "                        url(repoUrl)",
    "                        if (scmCredentialsId?.trim()) {",
    "                            credentials(scmCredentialsId)",
    "                        }",
    "                    }",
    "                    branch(branchSpec)",
    "                }",
    "            }",
    "            scriptPath(scriptPath)",
    "        }",
    "    }",
    "}",
    ""
)

foreach ($folderPath in $sortedFolderPaths) {
    $lines += ("folder({0}) {{" -f (ConvertTo-GroovyString -Value $folderPath))
    $lines += ("    description({0})" -f (ConvertTo-GroovyString -Value $folderDescriptions[$folderPath]))
    $lines += "}"
    $lines += ""
}

foreach ($selection in $selections) {
    foreach ($job in @($selection.PipelineJobs)) {
        $lines += Get-GeneratedPipelineJobDslLines `
            -Path ([string]$job.Path) `
            -Jenkinsfile ([string]$job.Jenkinsfile) `
            -DescriptionLines @(Get-BundlePipelineJobDescriptionLines -Selection $selection -Job $job)
    }
}

foreach ($serviceJob in $serviceJobs | Sort-Object Name) {
    $lines += Get-GeneratedPipelineJobDslLines `
        -Path ([string]$serviceJob.Path) `
        -Jenkinsfile ([string]$serviceJob.Jenkinsfile) `
        -DescriptionLines @(Get-ServicePipelineJobDescriptionLines -ServiceJob $serviceJob)
}

$document = $lines -join [Environment]::NewLine

Write-RepoDocument -RepoRoot $root -Path $OutputPath -Document $document -Description "Jenkins Job DSL"
