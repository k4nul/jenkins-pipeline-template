# Synthetic fixture builders for controller-free Jenkins validation.

function Invoke-JenkinsValidationFailureProbe {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @()
    )

    $failed = $false
    $message = ""

    try {
        & $ScriptBlock @ArgumentList
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    return [PSCustomObject]@{
        Failed = $failed
        Message = $message
    }
}

function Invoke-RepoOutputPathReparsePointFailureFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $targetPath = Join-Path -Path $OutputDirectory -ChildPath "reparse-target"
    $probeRoot = Join-Path -Path $OutputDirectory -ChildPath "reparse-probe"
    $linkPath = Join-Path -Path $probeRoot -ChildPath "linked-out"
    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null

    try {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
        }

        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -ErrorAction Stop | Out-Null
    }
    catch {
        return [PSCustomObject]@{
            Skipped = $true
            SkipMessage = [string]$_
            Failed = $false
            Message = ""
        }
    }

    try {
        $probePath = [System.IO.Path]::GetRelativePath($Root, (Join-Path -Path $linkPath -ChildPath "probe.txt"))
        $probe = Invoke-JenkinsValidationFailureProbe `
            -ScriptBlock {
                param(
                    [string]$ProbeRoot,
                    [string]$ProbePath
                )

                Resolve-RepoOutputPath -RepoRoot $ProbeRoot -Path $ProbePath | Out-Null
            } `
            -ArgumentList @($Root, $probePath)

        return [PSCustomObject]@{
            Skipped = $false
            SkipMessage = ""
            Failed = [bool]$probe.Failed
            Message = [string]$probe.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
        }
    }
}

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

function Invoke-ServiceValidationFixtureFailure {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fixture,

        [string]$Catalog
    )

    $catalogPath = ""
    if ($Fixture.PSObject.Properties.Match("CatalogPath").Count -gt 0) {
        $catalogPath = [string]$Fixture.CatalogPath
    }

    if ($PSBoundParameters.ContainsKey("Catalog")) {
        Set-Content -Path $catalogPath -Value $Catalog -Encoding utf8NoBOM
    }

    $probe = Invoke-JenkinsValidationFailureProbe `
        -ScriptBlock {
            param(
                [string]$ServiceValidationScript,
                [string]$FixtureRoot
            )

            & $ServiceValidationScript -RepoRoot $FixtureRoot 6>$null | Out-Null
        } `
        -ArgumentList @([string]$Fixture.ServiceValidationScript, [string]$Fixture.Root)

    return [PSCustomObject]@{
        Failed = [bool]$probe.Failed
        Message = [string]$probe.Message
        CatalogPath = $catalogPath
        Root = [string]$Fixture.Root
    }
}

function Invoke-MissingServiceJenkinsfileValidationFailureFixture {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-MissingServiceJenkinsfileFixtureContext -Root $Root -OutputDirectory $OutputDirectory
    return (Invoke-ServiceValidationFixtureFailure -Fixture $fixture)
}

function Invoke-UnsafeServiceCatalogNameFailureFixtures {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-UnsafeServiceCatalogFixtureContext -Root $Root -OutputDirectory $OutputDirectory
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($case in @(Get-UnsafeServiceCatalogNameCases)) {
        $probe = Invoke-ServiceValidationFixtureFailure -Fixture $fixture -Catalog ([string]$case.Catalog)
        $results.Add([PSCustomObject]@{
            Failed = [bool]$probe.Failed
            Message = [string]$probe.Message
            ExpectedMessage = [string]$case.ExpectedMessage
            AssertionMessage = [string]$case.Message
            CatalogPath = [string]$probe.CatalogPath
        }) | Out-Null
    }

    return @($results.ToArray())
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

function Invoke-UnsupportedServiceComposeUpdateFailureFixture {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-UnsupportedServiceComposeUpdateFixtureContext -Root $Root -OutputDirectory $OutputDirectory
    return (Invoke-ServiceValidationFixtureFailure -Fixture $fixture)
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

function Get-UnsafePromotionArchiveEntryCases {
    return @(
        @{
            EntryName = "../escaped.txt"
            ExpectedMessage = "parent-directory segments"
            Message = "Promotion should reject archive entries that traverse out of the extraction directory."
        },
        @{
            EntryName = "/absolute.txt"
            ExpectedMessage = "must be relative"
            Message = "Promotion should reject absolute archive entries."
        },
        @{
            EntryName = "nested/unsafe:name.txt"
            ExpectedMessage = "unsupported characters"
            Message = "Promotion should reject archive entries with platform-sensitive characters."
        }
    )
}

function Invoke-PromotionArchiveEntryFailureFixtures {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromotionScript,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $cases = @(Get-UnsafePromotionArchiveEntryCases)
    $results = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $cases.Count; $index++) {
        $case = $cases[$index]
        $archivePath = Join-Path $OutputDirectory ("unsafe-promotion-archive-{0}.zip" -f $index)
        $extractPath = Join-Path $OutputDirectory ("unsafe-promotion-extract-{0}" -f $index)
        $escapedPath = Join-Path $OutputDirectory "escaped.txt"

        if (Test-Path -Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
        if (Test-Path -Path $escapedPath -PathType Leaf) {
            Remove-Item -Path $escapedPath -Force
        }

        New-ZipArchiveFixture -ArchivePath $archivePath -EntryNames @("bundle-manifest.json", [string]$case.EntryName)

        $probe = Invoke-JenkinsValidationFailureProbe `
            -ScriptBlock {
                param(
                    [string]$Script,
                    [string]$RepoRoot,
                    [string]$ArchivePath,
                    [string]$ExtractPath
                )

                & $Script -RepoRoot $RepoRoot -ArchivePath $ArchivePath -ExtractPath $ExtractPath 6>$null | Out-Null
            } `
            -ArgumentList @($PromotionScript, $Root, $archivePath, $extractPath)

        $results.Add([PSCustomObject]@{
            Failed = [bool]$probe.Failed
            Message = [string]$probe.Message
            ExpectedMessage = [string]$case.ExpectedMessage
            AssertionMessage = [string]$case.Message
            EscapedPathExists = (Test-Path -Path $escapedPath -PathType Leaf)
            ArchivePath = $archivePath
            ExtractPath = $extractPath
        }) | Out-Null
    }

    return @($results.ToArray())
}
