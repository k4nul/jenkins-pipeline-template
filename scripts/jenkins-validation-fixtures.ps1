# Synthetic fixture builders for controller-free Jenkins validation.

function New-JenkinsServiceJobFixtureRoot {
    param(
        [string]$Root,
        [string]$OutputDirectory,
        [string]$Name = "service-job-fixture-repo"
    )

    $fixtureRoot = Join-Path -Path $OutputDirectory -ChildPath $Name
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
        New-Item -ItemType Directory -Path (Join-Path -Path $fixtureRoot -ChildPath $relativeDirectory) -Force | Out-Null
    }

    foreach ($scriptName in @(
        "environment-preset.ps1",
        "export-jenkins-job-dsl.ps1",
        "jenkins-job-dsl-common.ps1",
        "jenkins-job-common.ps1",
        "platform-catalog.ps1",
        "show-jenkins-job-plan.ps1",
        "validate-service-pipelines.ps1"
    )) {
        Copy-Item -Path (Join-Path -Path $Root -ChildPath "scripts/$scriptName") -Destination (Join-Path -Path $fixtureRoot -ChildPath "scripts/$scriptName")
    }

    Copy-Item -Path (Join-Path -Path $Root -ChildPath "config/profiles/*.psd1") -Destination (Join-Path -Path $fixtureRoot -ChildPath "config/profiles")
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "config/fixture-values.env.example") -Value "FIXTURE_VALUE=true" -Encoding utf8NoBOM

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
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "config/service-pipelines.psd1") -Value $catalog -Encoding utf8NoBOM

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
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "config/environments/fixture-alpha.psd1") -Value $fixturePresetAlpha -Encoding utf8NoBOM

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
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "config/environments/fixture-beta.psd1") -Value $fixturePresetBeta -Encoding utf8NoBOM

    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "services/nginx-web/README.md") -Value "# NGINX fixture service" -Encoding utf8NoBOM
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "services/nginx-web/docker-compose.yaml") -Value "services: {}" -Encoding utf8NoBOM
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "services/nginx-web/site/index.html") -Value "<h1>NGINX fixture service</h1>" -Encoding utf8NoBOM

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
    Set-Content -Path (Join-Path -Path $fixtureRoot -ChildPath "services/nginx-web/Jenkinsfile") -Value $jenkinsfile -Encoding utf8NoBOM

    return $fixtureRoot
}

function New-JenkinsServiceJobFixtureContext {
    param(
        [string]$Root,
        [string]$OutputDirectory,
        [string]$DslOutputDirectory = "out/jenkins/validation"
    )

    $fixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $Root -OutputDirectory $OutputDirectory
    $serviceJobFixtureDslOutputPath = Join-Path -Path $DslOutputDirectory -ChildPath "service-job-fixture-seed-job-dsl.groovy"
    $sharedServiceJobFixtureDslOutputPath = Join-Path -Path $DslOutputDirectory -ChildPath "shared-service-job-fixture-seed-job-dsl.groovy"

    return [PSCustomObject]@{
        Root = $fixtureRoot
        JobPlanScript = Join-Path -Path $fixtureRoot -ChildPath "scripts/show-jenkins-job-plan.ps1"
        JobDslScript = Join-Path -Path $fixtureRoot -ChildPath "scripts/export-jenkins-job-dsl.ps1"
        ServiceValidationScript = Join-Path -Path $fixtureRoot -ChildPath "scripts/validate-service-pipelines.ps1"
        ServiceJobDslOutputPath = $serviceJobFixtureDslOutputPath
        ServiceJobDslPath = Join-Path -Path $fixtureRoot -ChildPath $serviceJobFixtureDslOutputPath
        SharedServiceJobRoot = "team/services/images"
        SharedServiceJobDslOutputPath = $sharedServiceJobFixtureDslOutputPath
        SharedServiceJobDslPath = Join-Path -Path $fixtureRoot -ChildPath $sharedServiceJobFixtureDslOutputPath
    }
}

function New-MissingServiceJenkinsfileFixtureContext {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $Root -OutputDirectory $OutputDirectory -Name "missing-service-jenkinsfile-fixture-repo"
    Remove-Item -Path (Join-Path $fixtureRoot "services/nginx-web/Jenkinsfile") -Force

    return [PSCustomObject]@{
        Root = $fixtureRoot
        ServiceValidationScript = Join-Path $fixtureRoot "scripts/validate-service-pipelines.ps1"
    }
}

function New-UnsafeServiceCatalogFixtureContext {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $Root -OutputDirectory $OutputDirectory -Name "unsafe-service-catalog-fixture-repo"

    return [PSCustomObject]@{
        Root = $fixtureRoot
        CatalogPath = Join-Path $fixtureRoot "config/service-pipelines.psd1"
        ServiceValidationScript = Join-Path $fixtureRoot "scripts/validate-service-pipelines.ps1"
    }
}

function Get-UnsafeServiceCatalogNameCases {
    $catalogTemplate = @'
@{
    Services = @(
        @{
            Name = "__SERVICE_NAME__"
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
                "README.md"
            )
            ArtifactInputs = @()
            RequiredJenkinsStrings = @()
            Notes = "Synthetic service catalog name safety fixture."
        }
    )
}
'@

    return @(
        @{
            Catalog = $catalogTemplate.Replace("__SERVICE_NAME__", "..\outside")
            ExpectedMessage = "Service catalog entry name is not allowed"
            Message = "Service pipeline validation should reject service names with parent-directory path segments."
        },
        @{
            Catalog = $catalogTemplate.Replace("__SERVICE_NAME__", "team/nginx-web")
            ExpectedMessage = "Service catalog entry name is not allowed"
            Message = "Service pipeline validation should reject nested service path names."
        },
        @{
            Catalog = @'
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
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md"
            )
            ArtifactInputs = @()
            RequiredJenkinsStrings = @()
            Notes = "First duplicate fixture."
        }
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
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md"
            )
            ArtifactInputs = @()
            RequiredJenkinsStrings = @()
            Notes = "Second duplicate fixture."
        }
    )
}
'@
            ExpectedMessage = "Duplicate service catalog entry name is not allowed"
            Message = "Service pipeline validation should reject duplicate service catalog names."
        }
    )
}

function New-UnsupportedServiceComposeUpdateFixtureContext {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $Root -OutputDirectory $OutputDirectory -Name "unsupported-compose-update-fixture-repo"
    $catalogPath = Join-Path $fixtureRoot "config/service-pipelines.psd1"
    $catalog = Get-Content -Path $catalogPath -Raw

    Set-Content -Path $catalogPath -Value $catalog.Replace('ComposeUpdate = "none"', 'ComposeUpdate = "sometimes"') -Encoding utf8NoBOM

    return [PSCustomObject]@{
        Root = $fixtureRoot
        CatalogPath = $catalogPath
        ServiceValidationScript = Join-Path $fixtureRoot "scripts/validate-service-pipelines.ps1"
    }
}

function New-ZipArchiveFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string[]]$EntryNames
    )

    $archiveDirectory = Split-Path -Path $ArchivePath -Parent
    if ($archiveDirectory) {
        New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    }
    if (Test-Path -Path $ArchivePath -PathType Leaf) {
        Remove-Item -Path $ArchivePath -Force
    }

    $archive = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entryName in @($EntryNames)) {
            $entry = $archive.CreateEntry($entryName)
            if (-not $entryName.EndsWith("/")) {
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                try {
                    $writer.Write("fixture")
                }
                finally {
                    $writer.Dispose()
                }
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}
