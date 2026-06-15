String requireLiteralOutPath(String value, String parameterName) {
    String normalized = value == null ? '' : value.trim().replace('\\', '/')
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

String requireLiteralOutDirectoryPattern(String value, String parameterName) {
    String normalized = requireLiteralOutPath(value, parameterName)
    return normalized == 'out' ? 'out/**' : "${normalized}/**"
}

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'PROMOTION_ENVIRONMENT_PRESET', defaultValue: '', description: 'Optional environment preset name from config/environments.')
        string(name: 'PROMOTION_ARCHIVE_PATH', defaultValue: 'out/ci/web-platform.zip', description: 'Archive path to promote, relative to the workspace unless absolute.')
        string(name: 'PROMOTION_EXTRACT_PATH', defaultValue: 'out/promotion/web-platform', description: 'Extraction path for the promoted bundle, relative to the workspace unless absolute.')
        booleanParam(name: 'PROMOTION_CLEAN_EXTRACT_PATH', defaultValue: true, description: 'Replace the existing extract directory before unpacking the bundle.')
        booleanParam(name: 'PROMOTION_PREPARE_HELM_REPOS', defaultValue: false, description: 'Refresh Helm repositories before validation or deployment.')
        booleanParam(name: 'PROMOTION_INCLUDE_DEFERRED_COMPONENTS', defaultValue: false, description: 'Include deferred manifests during validation or deployment.')
        booleanParam(name: 'PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY', defaultValue: false, description: 'Fail if generated bootstrap secret YAML files still contain placeholders.')
        booleanParam(name: 'PROMOTION_REQUIRE_BOOTSTRAP_STATUS', defaultValue: false, description: 'Fail if bootstrap namespaces or secrets are not present in the current cluster context.')
        booleanParam(name: 'PROMOTION_SKIP_BUNDLE_VALIDATION', defaultValue: false, description: 'Skip validate-bundle.ps1 after the archive is extracted.')
        booleanParam(name: 'PROMOTION_DEPLOY', defaultValue: false, description: 'Run deploy-bundle.ps1 after promotion validation.')
        booleanParam(name: 'PROMOTION_DEPLOY_DRY_RUN', defaultValue: true, description: 'Run deployment in dry-run mode when PROMOTION_DEPLOY is enabled.')
    }

    environment {
        PROMOTION_ENVIRONMENT_PRESET = "${params.PROMOTION_ENVIRONMENT_PRESET}"
        PROMOTION_ARCHIVE_PATH = "${params.PROMOTION_ARCHIVE_PATH}"
        PROMOTION_EXTRACT_PATH = "${params.PROMOTION_EXTRACT_PATH}"
        PROMOTION_CLEAN_EXTRACT_PATH = "${params.PROMOTION_CLEAN_EXTRACT_PATH}"
        PROMOTION_PREPARE_HELM_REPOS = "${params.PROMOTION_PREPARE_HELM_REPOS}"
        PROMOTION_INCLUDE_DEFERRED_COMPONENTS = "${params.PROMOTION_INCLUDE_DEFERRED_COMPONENTS}"
        PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY = "${params.PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY}"
        PROMOTION_REQUIRE_BOOTSTRAP_STATUS = "${params.PROMOTION_REQUIRE_BOOTSTRAP_STATUS}"
        PROMOTION_SKIP_BUNDLE_VALIDATION = "${params.PROMOTION_SKIP_BUNDLE_VALIDATION}"
        PROMOTION_DEPLOY = "${params.PROMOTION_DEPLOY}"
        PROMOTION_DEPLOY_DRY_RUN = "${params.PROMOTION_DEPLOY_DRY_RUN}"
    }

    stages {
        stage('Agent Readiness') {
            steps {
                pwsh '''
function Test-TrueValue {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase))
}

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\validate-workstation.ps1'
$requiredTools = [System.Collections.Generic.List[string]]::new()
$needsClusterTools =
    -not (Test-TrueValue -Value $env:PROMOTION_SKIP_BUNDLE_VALIDATION) -or
    (Test-TrueValue -Value $env:PROMOTION_DEPLOY) -or
    (Test-TrueValue -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_STATUS) -or
    (Test-TrueValue -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY) -or
    (Test-TrueValue -Value $env:PROMOTION_PREPARE_HELM_REPOS)

if ($needsClusterTools) {
    $requiredTools.Add('kubectl') | Out-Null
    $requiredTools.Add('helm') | Out-Null
}

& $scriptPath `
    -ProfileName 'bundle promotion agent' `
    -RequiredTools @($requiredTools.ToArray()) `
    -OptionalTools @('git', 'docker', 'python') `
    -Strict
'''
            }
        }

        stage('Deployment Approval') {
            when {
                expression { return params.PROMOTION_DEPLOY && !params.PROMOTION_DEPLOY_DRY_RUN }
            }
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: 'Approve non-dry-run bundle promotion deployment?', ok: 'Approve deployment'
                }
            }
        }

        stage('Bundle Promotion') {
            steps {
                pwsh '''
function Add-OptionalSwitch {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Arguments.Add($Name) | Out-Null
    }
}

function Test-TrueValue {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase))
}

function Assert-LiteralOutPath {
    param(
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value
    )

    $normalized = ([string]$Value).Trim().Replace([char]92, [char]47)
    if (-not $normalized) {
        throw "$Name must not be empty before file output or artifact archiving."
    }
    if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:/') {
        throw "$Name must be workspace-relative and stay under out/."
    }
    if ($normalized -ne 'out' -and -not $normalized.StartsWith('out/')) {
        throw "$Name must stay under out/."
    }
    if ($normalized -match '[*?\[\]{}]') {
        throw "$Name must be a literal path, not a glob pattern."
    }

    $segments = @($normalized -split '/')
    if (@($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "$Name must not contain empty, current-directory, or parent-directory segments."
    }
}

if ((Test-TrueValue -Value $env:PROMOTION_DEPLOY) -and -not (Test-TrueValue -Value $env:PROMOTION_DEPLOY_DRY_RUN)) {
    if (-not (Test-TrueValue -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY)) {
        throw 'PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY must be true for non-dry-run deployments.'
    }

    if (-not (Test-TrueValue -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_STATUS)) {
        throw 'PROMOTION_REQUIRE_BOOTSTRAP_STATUS must be true for non-dry-run deployments.'
    }
}

Assert-LiteralOutPath -Name 'PROMOTION_ARCHIVE_PATH' -Value $env:PROMOTION_ARCHIVE_PATH
Assert-LiteralOutPath -Name 'PROMOTION_EXTRACT_PATH' -Value $env:PROMOTION_EXTRACT_PATH

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\invoke-bundle-promotion.ps1'
$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add('-RepoRoot') | Out-Null
$arguments.Add($env:WORKSPACE) | Out-Null
if ($env:PROMOTION_ENVIRONMENT_PRESET) {
    $arguments.Add('-EnvironmentPreset') | Out-Null
    $arguments.Add($env:PROMOTION_ENVIRONMENT_PRESET) | Out-Null
}
$arguments.Add('-ArchivePath') | Out-Null
$arguments.Add($env:PROMOTION_ARCHIVE_PATH) | Out-Null
$arguments.Add('-ExtractPath') | Out-Null
$arguments.Add($env:PROMOTION_EXTRACT_PATH) | Out-Null

Add-OptionalSwitch -Arguments $arguments -Name '-CleanExtractPath' -Value $env:PROMOTION_CLEAN_EXTRACT_PATH
Add-OptionalSwitch -Arguments $arguments -Name '-PrepareHelmRepos' -Value $env:PROMOTION_PREPARE_HELM_REPOS
Add-OptionalSwitch -Arguments $arguments -Name '-IncludeDeferredComponents' -Value $env:PROMOTION_INCLUDE_DEFERRED_COMPONENTS
Add-OptionalSwitch -Arguments $arguments -Name '-RequireBootstrapSecretsReady' -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY
Add-OptionalSwitch -Arguments $arguments -Name '-RequireBootstrapStatus' -Value $env:PROMOTION_REQUIRE_BOOTSTRAP_STATUS
Add-OptionalSwitch -Arguments $arguments -Name '-SkipBundleValidation' -Value $env:PROMOTION_SKIP_BUNDLE_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-DeployBundle' -Value $env:PROMOTION_DEPLOY
Add-OptionalSwitch -Arguments $arguments -Name '-DeploymentDryRun' -Value $env:PROMOTION_DEPLOY_DRY_RUN

$argumentArray = @($arguments.ToArray())
& $scriptPath @argumentArray
'''
            }
        }
    }

    post {
        always {
            script {
                def archivePatterns = []
                if (params.PROMOTION_ARCHIVE_PATH?.trim()) {
                    archivePatterns << requireLiteralOutPath(params.PROMOTION_ARCHIVE_PATH, 'PROMOTION_ARCHIVE_PATH')
                }
                if (params.PROMOTION_EXTRACT_PATH?.trim()) {
                    archivePatterns << requireLiteralOutDirectoryPattern(params.PROMOTION_EXTRACT_PATH, 'PROMOTION_EXTRACT_PATH')
                }

                if (!archivePatterns.isEmpty()) {
                    archiveArtifacts artifacts: archivePatterns.join(','), allowEmptyArchive: true, fingerprint: true
                }
            }
        }
    }
}
