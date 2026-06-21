String requireLiteralOutPath(String value, String parameterName) {
    String rawValue = value == null ? '' : value
    if (rawValue ==~ /.*[\u0000-\u001F\u007F].*/) {
        throw new IllegalArgumentException("${parameterName} must not contain control characters.")
    }
    String normalized = rawValue.trim().replace('\\', '/')
    if (!normalized) {
        throw new IllegalArgumentException("${parameterName} must not be empty before using it as a Jenkins artifact path.")
    }
    if (normalized.startsWith('/') || normalized ==~ /^[A-Za-z]:\/.*/) {
        throw new IllegalArgumentException("${parameterName} must be workspace-relative and stay under out/.")
    }
    if (normalized != 'out' && !normalized.startsWith('out/')) {
        throw new IllegalArgumentException("${parameterName} must stay under out/.")
    }
    ['*', '?', '[', ']', '{', '}'].each { token ->
        if (normalized.contains(token)) {
            throw new IllegalArgumentException("${parameterName} must be a literal path, not an Ant glob pattern.")
        }
    }

    def pathSegments = normalized.split('/') as List
    if (pathSegments.any { segment -> segment == '.' || segment == '..' || segment == '' }) {
        throw new IllegalArgumentException("${parameterName} must not contain empty, current-directory, or parent-directory segments.")
    }

    return normalized
}

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'SEED_ENVIRONMENT_PRESETS', defaultValue: '', description: 'Optional comma-separated preset names from config/environments. Leave blank to use every preset found there, or define a custom selection below.')
        string(name: 'SEED_SELECTION_NAME', defaultValue: '', description: 'Optional custom selection name used when you generate jobs without an environment preset.')
        string(name: 'SEED_PROFILE', defaultValue: '', description: 'Optional bundle profile override when you want a custom selection instead of the preset defaults.')
        string(name: 'SEED_APPLICATIONS', defaultValue: '', description: 'Optional comma-separated application templates for a custom selection.')
        string(name: 'SEED_DATA_SERVICES', defaultValue: '', description: 'Optional comma-separated data services for a custom selection.')
        string(name: 'SEED_VALUES_FILE', defaultValue: '', description: 'Optional values file override for a custom selection.')
        string(name: 'SEED_DOCKER_REGISTRY', defaultValue: '', description: 'Optional registry override for a custom selection.')
        string(name: 'SEED_VERSION', defaultValue: '', description: 'Optional version override for a custom selection.')
        string(name: 'SEED_BUNDLE_OUTPUT_PATH', defaultValue: '', description: 'Optional bundle output path override for a custom selection.')
        string(name: 'SEED_ARCHIVE_PATH', defaultValue: '', description: 'Optional bundle archive path override for a custom selection.')
        string(name: 'SEED_PROMOTION_EXTRACT_PATH', defaultValue: '', description: 'Optional promotion extract path override for a custom selection.')
        string(name: 'SEED_REPO_URL', defaultValue: '', description: 'Repository URL used by generated SCM-backed pipeline jobs. Required before applying the generated DSL.')
        string(name: 'SEED_BRANCH_SPEC', defaultValue: '', description: 'Git branch spec used by generated SCM-backed pipeline jobs. Required before applying the generated DSL.')
        string(name: 'SEED_SCM_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credentials ID parameter used for SCM checkout in the generated jobs.')
        string(name: 'SEED_JOB_ROOT', defaultValue: 'platform', description: 'Root Jenkins folder for validation, delivery, and promotion jobs.')
        string(name: 'SEED_SERVICE_JOB_ROOT', defaultValue: 'services', description: 'Root Jenkins folder for service image jobs.')
        string(name: 'SEED_OUTPUT_PATH', defaultValue: 'out/jenkins/seed-job-dsl.groovy', description: 'Workspace-relative path where the generated Job DSL Groovy file will be written.')
        booleanParam(name: 'SEED_INCLUDE_JENKINS', defaultValue: false, description: 'Include Jenkins-related bundle components in the generated bundle job parameter defaults.')
        booleanParam(name: 'SEED_SKIP_SERVICE_JOBS', defaultValue: false, description: 'Skip service image pipeline job generation and only generate the bundle job chain.')
        booleanParam(name: 'SEED_USE_LIGHTWEIGHT_CHECKOUT', defaultValue: true, description: 'Enable lightweight checkout on the generated SCM-backed pipeline jobs.')
        booleanParam(name: 'SEED_APPLY_JOB_DSL', defaultValue: false, description: 'Apply the generated Job DSL immediately by using the Jenkins Job DSL plugin.')
        choice(name: 'SEED_REMOVED_JOB_ACTION', choices: ['IGNORE', 'DISABLE', 'DELETE'], description: 'Behavior for previously generated jobs that are missing from the refreshed DSL when SEED_APPLY_JOB_DSL is enabled.')
        booleanParam(name: 'SEED_CONFIRM_REMOVED_JOB_DELETE', defaultValue: false, description: 'Required confirmation before SEED_APPLY_JOB_DSL can run with SEED_REMOVED_JOB_ACTION=DELETE.')
    }

    environment {
        SEED_ENVIRONMENT_PRESETS = "${params.SEED_ENVIRONMENT_PRESETS}"
        SEED_SELECTION_NAME = "${params.SEED_SELECTION_NAME}"
        SEED_PROFILE = "${params.SEED_PROFILE}"
        SEED_APPLICATIONS = "${params.SEED_APPLICATIONS}"
        SEED_DATA_SERVICES = "${params.SEED_DATA_SERVICES}"
        SEED_VALUES_FILE = "${params.SEED_VALUES_FILE}"
        SEED_DOCKER_REGISTRY = "${params.SEED_DOCKER_REGISTRY}"
        SEED_VERSION = "${params.SEED_VERSION}"
        SEED_BUNDLE_OUTPUT_PATH = "${params.SEED_BUNDLE_OUTPUT_PATH}"
        SEED_ARCHIVE_PATH = "${params.SEED_ARCHIVE_PATH}"
        SEED_PROMOTION_EXTRACT_PATH = "${params.SEED_PROMOTION_EXTRACT_PATH}"
        SEED_REPO_URL = "${params.SEED_REPO_URL}"
        SEED_BRANCH_SPEC = "${params.SEED_BRANCH_SPEC}"
        SEED_SCM_CREDENTIALS_ID = "${params.SEED_SCM_CREDENTIALS_ID}"
        SEED_JOB_ROOT = "${params.SEED_JOB_ROOT}"
        SEED_SERVICE_JOB_ROOT = "${params.SEED_SERVICE_JOB_ROOT}"
        SEED_OUTPUT_PATH = "${params.SEED_OUTPUT_PATH}"
        SEED_INCLUDE_JENKINS = "${params.SEED_INCLUDE_JENKINS}"
        SEED_SKIP_SERVICE_JOBS = "${params.SEED_SKIP_SERVICE_JOBS}"
        SEED_USE_LIGHTWEIGHT_CHECKOUT = "${params.SEED_USE_LIGHTWEIGHT_CHECKOUT}"
        SEED_APPLY_JOB_DSL = "${params.SEED_APPLY_JOB_DSL}"
        SEED_REMOVED_JOB_ACTION = "${params.SEED_REMOVED_JOB_ACTION}"
        SEED_CONFIRM_REMOVED_JOB_DELETE = "${params.SEED_CONFIRM_REMOVED_JOB_DELETE}"
    }

    stages {
        stage('Seed Preflight') {
            steps {
                pwsh '''
$scriptPath = Join-Path $env:WORKSPACE 'scripts\\validate-workstation.ps1'
& $scriptPath `
    -ProfileName 'job seed generation agent' `
    -RequiredTools @() `
    -OptionalTools @('git') `
    -Strict
'''
            }
        }

        stage('Generate Job DSL') {
            steps {
                pwsh '''
function Set-ArgumentValue {
    param(
        [hashtable]$Arguments,
        [string]$Name,
        [object]$Value
    )

    $Arguments[$Name.TrimStart([char]'-')] = $Value
}

function Add-OptionalListArgument {
    param(
        [hashtable]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if (-not $Value) {
        return
    }

    $entries = @($Value -split '\\s*,\\s*' | Where-Object { $_ })
    if ($entries.Count -eq 0) {
        return
    }

    Set-ArgumentValue -Arguments $Arguments -Name $Name -Value @($entries)
}

function Add-OptionalStringArgument {
    param(
        [hashtable]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if (-not $Value) {
        return
    }

    Set-ArgumentValue -Arguments $Arguments -Name $Name -Value $Value
}

function Add-OptionalSwitch {
    param(
        [hashtable]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ArgumentValue -Arguments $Arguments -Name $Name -Value $true
    }
}

function Test-TrueValue {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase))
}

function Add-BooleanArgument {
    param(
        [hashtable]$Arguments,
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value,
        [bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Set-ArgumentValue -Arguments $Arguments -Name $Name -Value $Default
        return
    }

    Set-ArgumentValue -Arguments $Arguments -Name $Name -Value (Test-TrueValue -Value $Value)
}

function Assert-ConcreteScmParameter {
    param(
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value,
        [string[]]$DisallowedValues = @()
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must be set before SEED_APPLY_JOB_DSL=true."
    }

    if ($DisallowedValues -contains $Value.Trim()) {
        throw "$Name must be changed from its public-safe placeholder before SEED_APPLY_JOB_DSL=true."
    }
}

function Assert-NoControlCharacters {
    param(
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -match "[\x00-\x1F\x7F]") {
        throw "$Name must not contain control characters."
    }
}

function Assert-SeedRepoUrlSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name 'SEED_REPO_URL' -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq 'REPLACE_WITH_REPOSITORY_URL') {
        return
    }

    if ($trimmed -match '\s') {
        throw 'SEED_REPO_URL must not contain whitespace.'
    }

    if ($trimmed -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        [System.Uri]$parsedUri = $null
        if (-not [System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$parsedUri)) {
            throw 'SEED_REPO_URL must be an absolute URI or a Git scp-like repository path.'
        }

        $allowedSchemes = @('https', 'ssh', 'git+ssh')
        if ($allowedSchemes -notcontains $parsedUri.Scheme.ToLowerInvariant()) {
            throw 'SEED_REPO_URL scheme must be one of https, ssh, or git+ssh.'
        }

        if ([string]::IsNullOrWhiteSpace($parsedUri.Host)) {
            throw 'SEED_REPO_URL absolute URIs must include a host.'
        }

        $hasEmbeddedCredential = -not [string]::IsNullOrEmpty($parsedUri.UserInfo)
        $hasSshUser = $parsedUri.Scheme -in @('ssh', 'git+ssh') -and $parsedUri.UserInfo -match '^[A-Za-z0-9._-]+$'
        if ($hasEmbeddedCredential -and -not $hasSshUser) {
            throw 'SEED_REPO_URL must not include embedded credentials; configure repository access with SEED_SCM_CREDENTIALS_ID.'
        }

        return
    }

    if ($trimmed -match '^[A-Za-z0-9._-]+@[^@\s:/\\]+:[^/\\\s].+$') {
        return
    }

    throw 'SEED_REPO_URL must be an HTTPS/SSH absolute URI or a Git scp-like repository path.'
}

function Assert-SeedBranchSpecSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name 'SEED_BRANCH_SPEC' -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq 'REPLACE_WITH_BRANCH_SPEC') {
        return
    }

    if ($trimmed -ne $Value) {
        throw 'SEED_BRANCH_SPEC must not contain leading or trailing whitespace.'
    }

    if ($trimmed -match '\s') {
        throw 'SEED_BRANCH_SPEC must not contain whitespace.'
    }

    if ($trimmed.Contains('..')) {
        throw "SEED_BRANCH_SPEC must not contain '..'."
    }

    if ($trimmed -notmatch '^[A-Za-z0-9._/@*+-]+$') {
        throw "SEED_BRANCH_SPEC must contain only letters, digits, '.', '_', '-', '/', '*', '+', or '@'."
    }
}

function Assert-SeedScmCredentialsIdSafety {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return
    }

    Assert-NoControlCharacters -Name 'SEED_SCM_CREDENTIALS_ID' -Value $Value
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed -ne $Value) {
        throw 'SEED_SCM_CREDENTIALS_ID must not contain leading or trailing whitespace.'
    }

    if ($trimmed -match '\s') {
        throw 'SEED_SCM_CREDENTIALS_ID must not contain whitespace.'
    }

    if ($trimmed -notmatch '^[A-Za-z0-9_.@-]+$') {
        throw "SEED_SCM_CREDENTIALS_ID must contain only letters, digits, '.', '_', '@', or '-'."
    }
}

Assert-SeedRepoUrlSafety -Value $env:SEED_REPO_URL
Assert-SeedBranchSpecSafety -Value $env:SEED_BRANCH_SPEC
Assert-SeedScmCredentialsIdSafety -Value $env:SEED_SCM_CREDENTIALS_ID

if (Test-TrueValue -Value $env:SEED_APPLY_JOB_DSL) {
    Assert-ConcreteScmParameter -Name 'SEED_REPO_URL' -Value $env:SEED_REPO_URL -DisallowedValues @('REPLACE_WITH_REPOSITORY_URL')
    Assert-ConcreteScmParameter -Name 'SEED_BRANCH_SPEC' -Value $env:SEED_BRANCH_SPEC -DisallowedValues @('REPLACE_WITH_BRANCH_SPEC')

    if ($env:SEED_REMOVED_JOB_ACTION -eq 'DELETE' -and -not (Test-TrueValue -Value $env:SEED_CONFIRM_REMOVED_JOB_DELETE)) {
        throw 'SEED_CONFIRM_REMOVED_JOB_DELETE must be true before applying Job DSL with SEED_REMOVED_JOB_ACTION=DELETE.'
    }
}

if (-not (Test-TrueValue -Value $env:SEED_SKIP_SERVICE_JOBS)) {
    $serviceValidationScriptPath = Join-Path $env:WORKSPACE 'scripts\\validate-service-pipelines.ps1'
    & $serviceValidationScriptPath -RepoRoot $env:WORKSPACE
}

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\export-jenkins-job-dsl.ps1'
$arguments = @{}
Set-ArgumentValue -Arguments $arguments -Name '-RepoRoot' -Value $env:WORKSPACE
Set-ArgumentValue -Arguments $arguments -Name '-OutputPath' -Value $env:SEED_OUTPUT_PATH
Set-ArgumentValue -Arguments $arguments -Name '-JobRoot' -Value $env:SEED_JOB_ROOT
Set-ArgumentValue -Arguments $arguments -Name '-ServiceJobRoot' -Value $env:SEED_SERVICE_JOB_ROOT
Add-BooleanArgument -Arguments $arguments -Name '-UseLightweightCheckout' -Value $env:SEED_USE_LIGHTWEIGHT_CHECKOUT -Default $true

Add-OptionalListArgument -Arguments $arguments -Name '-EnvironmentPreset' -Value $env:SEED_ENVIRONMENT_PRESETS
Add-OptionalListArgument -Arguments $arguments -Name '-Applications' -Value $env:SEED_APPLICATIONS
Add-OptionalListArgument -Arguments $arguments -Name '-DataServices' -Value $env:SEED_DATA_SERVICES
Add-OptionalStringArgument -Arguments $arguments -Name '-SelectionName' -Value $env:SEED_SELECTION_NAME
Add-OptionalStringArgument -Arguments $arguments -Name '-Profile' -Value $env:SEED_PROFILE
Add-OptionalStringArgument -Arguments $arguments -Name '-ValuesFile' -Value $env:SEED_VALUES_FILE
Add-OptionalStringArgument -Arguments $arguments -Name '-DockerRegistry' -Value $env:SEED_DOCKER_REGISTRY
Add-OptionalStringArgument -Arguments $arguments -Name '-Version' -Value $env:SEED_VERSION
Add-OptionalStringArgument -Arguments $arguments -Name '-BundleOutputPath' -Value $env:SEED_BUNDLE_OUTPUT_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-ArchivePath' -Value $env:SEED_ARCHIVE_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-PromotionExtractPath' -Value $env:SEED_PROMOTION_EXTRACT_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-RepoUrl' -Value $env:SEED_REPO_URL
Add-OptionalStringArgument -Arguments $arguments -Name '-BranchSpec' -Value $env:SEED_BRANCH_SPEC
Add-OptionalStringArgument -Arguments $arguments -Name '-ScmCredentialsId' -Value $env:SEED_SCM_CREDENTIALS_ID
Add-OptionalSwitch -Arguments $arguments -Name '-IncludeJenkins' -Value $env:SEED_INCLUDE_JENKINS
Add-OptionalSwitch -Arguments $arguments -Name '-SkipServiceJobs' -Value $env:SEED_SKIP_SERVICE_JOBS

$argumentArray = $arguments
& $scriptPath @argumentArray
'''
            }
        }

        stage('Apply Job DSL') {
            when {
                expression { return params.SEED_APPLY_JOB_DSL }
            }
            steps {
                script {
                    jobDsl(
                        targets: requireLiteralOutPath(params.SEED_OUTPUT_PATH, 'SEED_OUTPUT_PATH'),
                        removedJobAction: params.SEED_REMOVED_JOB_ACTION,
                        removedViewAction: 'IGNORE',
                        lookupStrategy: 'JENKINS_ROOT'
                    )
                }
            }
        }
    }

    post {
        always {
            script {
                def hasConcreteGeneratedMetadata =
                    (params.SEED_REPO_URL?.trim() && params.SEED_REPO_URL.trim() != 'REPLACE_WITH_REPOSITORY_URL') ||
                    (params.SEED_BRANCH_SPEC?.trim() && params.SEED_BRANCH_SPEC.trim() != 'REPLACE_WITH_BRANCH_SPEC') ||
                    params.SEED_SCM_CREDENTIALS_ID?.trim() ||
                    params.SEED_DOCKER_REGISTRY?.trim()

                if (hasConcreteGeneratedMetadata) {
                    echo 'Skipping generated Job DSL artifact archive because concrete SCM, registry, or credential metadata was supplied.'
                } else {
                    archiveArtifacts artifacts: requireLiteralOutPath(params.SEED_OUTPUT_PATH, 'SEED_OUTPUT_PATH'), allowEmptyArchive: true, fingerprint: true
                }
            }
        }
    }
}
