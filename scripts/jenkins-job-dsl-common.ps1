# Shared helpers for Jenkins Job DSL export scripts.

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

    $normalized = ([string]$Path).Trim().Replace("\", "/")
    if (-not $normalized) {
        throw "Jenkinsfile path must not be empty."
    }

    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith("/")) {
        throw ("Jenkinsfile path must be repository-relative: {0}" -f $Path)
    }

    if ($normalized -match "[\x00-\x1F\x7F*?\[\]{}]") {
        throw ("Jenkinsfile path must be a literal repository-relative path: {0}" -f $Path)
    }

    $segments = @($normalized -split "/")
    if (@($segments | Where-Object { $_ -eq "" -or $_ -eq "." -or $_ -eq ".." }).Count -gt 0) {
        throw ("Jenkinsfile path must not contain empty, current-directory, or parent-directory segments: {0}" -f $Path)
    }

    $leafName = [System.IO.Path]::GetFileName($normalized)
    if ($leafName -ne "Jenkinsfile" -and -not $leafName.EndsWith(".Jenkinsfile", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Jenkinsfile path must point to a Jenkinsfile: {0}" -f $Path)
    }

    return $normalized
}

function Assert-NoControlCharacters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -match "[\x00-\x1F\x7F]") {
        throw ("{0} must not contain control characters." -f $Name)
    }
}

function Assert-RepoUrlSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name "RepoUrl" -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()

    if ($trimmed -eq "REPLACE_WITH_REPOSITORY_URL") {
        return
    }

    if ($trimmed -match "\s") {
        throw "RepoUrl must not contain whitespace."
    }

    if ($trimmed -match "^[A-Za-z][A-Za-z0-9+.-]*://") {
        [System.Uri]$parsedUri = $null
        if (-not [System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$parsedUri)) {
            throw "RepoUrl must be an absolute URI or a Git scp-like repository path."
        }

        $allowedSchemes = @("https", "ssh", "git+ssh")
        if ($allowedSchemes -notcontains $parsedUri.Scheme.ToLowerInvariant()) {
            throw "RepoUrl scheme must be one of https, ssh, or git+ssh."
        }

        if ([string]::IsNullOrWhiteSpace($parsedUri.Host)) {
            throw "RepoUrl absolute URIs must include a host."
        }

        $hasEmbeddedCredential = -not [string]::IsNullOrEmpty($parsedUri.UserInfo)
        $hasSshUser = $parsedUri.Scheme -in @("ssh", "git+ssh") -and $parsedUri.UserInfo -match "^[A-Za-z0-9._-]+$"
        if ($hasEmbeddedCredential -and -not $hasSshUser) {
            throw "RepoUrl must not include embedded credentials; configure repository access with -ScmCredentialsId."
        }

        return
    }

    if ($trimmed -match "^[A-Za-z0-9._-]+@[^@\s:/\\]+:[^/\\\s].+$") {
        return
    }

    throw "RepoUrl must be an HTTPS/SSH absolute URI or a Git scp-like repository path."
}

function Assert-BranchSpecSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name "BranchSpec" -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq "REPLACE_WITH_BRANCH_SPEC") {
        return
    }

    if ($trimmed -ne $Value) {
        throw "BranchSpec must not contain leading or trailing whitespace."
    }

    if ($trimmed -match "\s") {
        throw "BranchSpec must not contain whitespace."
    }

    if ($trimmed.Contains("..")) {
        throw "BranchSpec must not contain '..'."
    }

    if ($trimmed -notmatch "^[A-Za-z0-9._/@*+-]+$") {
        throw "BranchSpec must contain only letters, digits, '.', '_', '-', '/', '*', '+', or '@'."
    }
}

function Assert-ScmCredentialsIdSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name "ScmCredentialsId" -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed -ne $Value) {
        throw "ScmCredentialsId must not contain leading or trailing whitespace."
    }

    if ($trimmed -match "\s") {
        throw "ScmCredentialsId must not contain whitespace."
    }

    if ($trimmed -notmatch "^[A-Za-z0-9_.@-]+$") {
        throw "ScmCredentialsId must contain only letters, digits, '.', '_', '@', or '-'."
    }
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
