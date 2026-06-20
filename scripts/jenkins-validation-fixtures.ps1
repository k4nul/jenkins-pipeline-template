# Synthetic fixture builders for controller-free Jenkins validation.

function New-JenkinsServiceJobFixtureRoot {
    param(
        [string]$Root,
        [string]$OutputDirectory,
        [string]$Name = "service-job-fixture-repo"
    )

    $fixtureRoot = Join-Path $OutputDirectory $Name
    if (Test-Path -Path $fixtureRoot) {
        Remove-Item -Path $fixtureRoot -Recurse -Force
    }

    foreach ($relativeDirectory in @(
        "config",
        "config/environments",
        "config/profiles",
        "scripts",
        "services/nginx-web",
        "services/nginx-web/site"
    )) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $relativeDirectory) -Force | Out-Null
    }

    foreach ($scriptName in @(
        "environment-preset.ps1",
        "export-jenkins-job-dsl.ps1",
        "jenkins-job-common.ps1",
        "platform-catalog.ps1",
        "show-jenkins-job-plan.ps1",
        "validate-service-pipelines.ps1"
    )) {
        Copy-Item -Path (Join-Path $Root "scripts/$scriptName") -Destination (Join-Path $fixtureRoot "scripts/$scriptName")
    }

    Copy-Item -Path (Join-Path $Root "config/profiles/*.psd1") -Destination (Join-Path $fixtureRoot "config/profiles")
    Set-Content -Path (Join-Path $fixtureRoot "config/fixture-values.env.example") -Value "FIXTURE_VALUE=true" -Encoding utf8NoBOM

    $catalog = @'
@{
    Services = @(
        @{
            Name = "nginx-web"
            Category = "fixture-service"
            ImageName = "fixture/nginx-web:1.0.0"
            BuildTagStrategy = "none"
            RequiresMode = $false
            UsesCacheToggle = $false
            UsesModeBuildArg = $false
            ComposeUpdate = "none"
            RequiresRegistry = $true
            HasJenkinsfile = $true
            OptionalEnvVars = @(
                "CACHE"
            )
            RequiredFiles = @(
                "README.md",
                "docker-compose.yaml",
                "site\index.html"
            )
            ArtifactInputs = @(
                "Consumes the bundle validation output before publishing a service image."
            )
            RequiredJenkinsStrings = @(
                "stage('Build')",
                "docker.withRegistry("
            )
            Notes = "Synthetic public-safe fixture for Jenkinsfile-backed service job projection."
        }
    )
}
'@
    Set-Content -Path (Join-Path $fixtureRoot "config/service-pipelines.psd1") -Value $catalog -Encoding utf8NoBOM

    $fixturePresetAlpha = @'
@{
    Description = "Fixture alpha preset selecting a shared Jenkinsfile-backed service."
    ValuesFile = "config\fixture-values.env.example"
    Version = "0.1.0-alpha"
    Profile = "web-platform"
    Applications = @(
        "nginx-web"
    )
    DataServices = @()
    IncludeJenkins = $false
    OutputPath = "out\delivery\fixture-alpha"
    ArchivePath = "out\delivery\fixture-alpha.zip"
    PromotionExtractPath = "out\promotion\fixture-alpha"
}
'@
    Set-Content -Path (Join-Path $fixtureRoot "config/environments/fixture-alpha.psd1") -Value $fixturePresetAlpha -Encoding utf8NoBOM

    $fixturePresetBeta = @'
@{
    Description = "Fixture beta preset selecting the same shared Jenkinsfile-backed service."
    ValuesFile = "config\fixture-values.env.example"
    Version = "0.1.0-beta"
    Profile = "web-platform"
    Applications = @(
        "nginx-web"
    )
    DataServices = @()
    IncludeJenkins = $false
    OutputPath = "out\delivery\fixture-beta"
    ArchivePath = "out\delivery\fixture-beta.zip"
    PromotionExtractPath = "out\promotion\fixture-beta"
}
'@
    Set-Content -Path (Join-Path $fixtureRoot "config/environments/fixture-beta.psd1") -Value $fixturePresetBeta -Encoding utf8NoBOM

    Set-Content -Path (Join-Path $fixtureRoot "services/nginx-web/README.md") -Value "# NGINX fixture service" -Encoding utf8NoBOM
    Set-Content -Path (Join-Path $fixtureRoot "services/nginx-web/docker-compose.yaml") -Value "services: {}" -Encoding utf8NoBOM
    Set-Content -Path (Join-Path $fixtureRoot "services/nginx-web/site/index.html") -Value "<h1>NGINX fixture service</h1>" -Encoding utf8NoBOM

    $jenkinsfile = @'
pipeline {
    agent any
    environment {
        DOCKER_IMAGE = "fixture/nginx-web:1.0.0"
        DOCKER_CREDENTIALS_ID = "fixture-docker-registry"
    }
    stages {
        stage('Build') {
            steps {
                script {
                    def app = docker.build("${DOCKER_IMAGE}")
                    docker.withRegistry('', DOCKER_CREDENTIALS_ID) {
                        app.push("${env.BUILD_NUMBER}")
                    }
                }
            }
        }
    }
}
'@
    Set-Content -Path (Join-Path $fixtureRoot "services/nginx-web/Jenkinsfile") -Value $jenkinsfile -Encoding utf8NoBOM

    return $fixtureRoot
}
