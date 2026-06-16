# Shared assertions for Jenkins Job DSL validation and public preset tests.

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw ("Assertion failed: {0}" -f $Message)
    }
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("Assertion failed: {0}. Expected '{1}', found '{2}'." -f $Message, $Expected, $Actual)
    }
}

function Assert-ContainsItem {
    param(
        [object[]]$Values,
        [string]$Expected,
        [string]$Message
    )

    $items = @($Values | ForEach-Object { [string]$_ })
    Assert-Condition -Condition ($items -contains $Expected) -Message $Message
}

function Assert-TextContains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Message,
        [string]$Context
    )

    if (-not $Message) {
        $Message = ("{0} is missing expected text: {1}" -f $Context, $Expected)
    }

    Assert-Condition -Condition $Text.Contains($Expected) -Message $Message
}

function Assert-TextNotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    Assert-Condition -Condition (-not ($Text -match $Pattern)) -Message $Message
}

function Invoke-JsonScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $json = (& $ScriptPath @Arguments | Out-String).Trim()
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($json)) -Message ("{0} returned empty JSON output." -f $ScriptPath)
    return ($json | ConvertFrom-Json)
}

function Get-PresetNames {
    param(
        [string]$Root,
        [string[]]$RequestedPresets = @()
    )

    $normalized = @(Get-NormalizedList -Values $RequestedPresets)
    if ($normalized.Count -gt 0) {
        return @($normalized)
    }

    $presetDirectory = Join-Path $Root "config/environments"
    return @(
        Get-ChildItem -Path $presetDirectory -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
}

function Get-JenkinsValidationPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    return [PSCustomObject]@{
        JobPlanScript = Join-Path $Root "scripts/show-jenkins-job-plan.ps1"
        ServicePlanScript = Join-Path $Root "scripts/show-service-pipeline-plan.ps1"
        JobDslScript = Join-Path $Root "scripts/export-jenkins-job-dsl.ps1"
        ServiceValidationScript = Join-Path $Root "scripts/validate-service-pipelines.ps1"
        WorkstationValidationScript = Join-Path $Root "scripts/validate-workstation.ps1"
        RepositoryValidationScript = Join-Path $Root "scripts/invoke-repository-validation.ps1"
        BundleDeliveryScript = Join-Path $Root "scripts/invoke-bundle-delivery.ps1"
        BundlePromotionScript = Join-Path $Root "scripts/invoke-bundle-promotion.ps1"
        PublicPresetTestScript = Join-Path $Root "tests/jenkins-job-dsl.public-presets.ps1"
        HelmConfigFile = Join-Path $Root "config/helm-releases.psd1"
        SeedJobPath = Join-Path $Root "jenkins/job-seed.Jenkinsfile"
        DeliveryJobPath = Join-Path $Root "jenkins/bundle-delivery.Jenkinsfile"
        PromotionJobPath = Join-Path $Root "jenkins/bundle-promotion.Jenkinsfile"
        RepositoryJobPath = Join-Path $Root "jenkins/repository-validation.Jenkinsfile"
    }
}

function Assert-RepoRelativeFileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Path)) -Message ("{0} must not be empty." -f $Description)
    Assert-Condition -Condition (-not ([System.IO.Path]::IsPathRooted($Path))) -Message ("{0} must be repository-relative: {1}" -f $Description, $Path)
    Assert-Condition -Condition (-not ($Path -match "[*?\[\]{}]")) -Message ("{0} must be a literal path: {1}" -f $Description, $Path)

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $Path))
    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    Assert-Condition `
        -Condition ($resolvedPath -ne $resolvedRoot -and $resolvedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) `
        -Message ("{0} must resolve inside the repository: {1}" -f $Description, $Path)
    Assert-Condition -Condition (Test-Path -Path $resolvedPath -PathType Leaf) -Message ("{0} was not found: {1}" -f $Description, $Path)

    return $resolvedPath
}

function Assert-JenkinsRuntimeContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [string[]]$Presets = @()
    )

    foreach ($scriptPath in @(
        $Paths.WorkstationValidationScript,
        $Paths.RepositoryValidationScript,
        $Paths.BundleDeliveryScript,
        $Paths.BundlePromotionScript,
        $Paths.PublicPresetTestScript
    )) {
        Assert-Condition -Condition (Test-Path -Path $scriptPath -PathType Leaf) -Message ("Jenkins runtime contract file should exist: {0}" -f $scriptPath)
    }

    Assert-Condition -Condition (Test-Path -Path $Paths.HelmConfigFile -PathType Leaf) -Message ("Public-safe Helm release catalog should exist: {0}" -f $Paths.HelmConfigFile)

    $repositoryJenkinsfile = Get-Content -Path $Paths.RepositoryJobPath -Raw
    $deliveryJenkinsfile = Get-Content -Path $Paths.DeliveryJobPath -Raw
    $promotionJenkinsfile = Get-Content -Path $Paths.PromotionJobPath -Raw
    $seedJenkinsfile = Get-Content -Path $Paths.SeedJobPath -Raw

    Assert-TextContains -Text $repositoryJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Repository validation job should call the committed workstation validator."
    Assert-TextContains -Text $repositoryJenkinsfile -Expected "scripts\\invoke-repository-validation.ps1" -Message "Repository validation job should call the committed repository validation entrypoint."
    Assert-TextContains -Text $deliveryJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Bundle delivery job should call the committed workstation validator."
    Assert-TextContains -Text $deliveryJenkinsfile -Expected "scripts\\invoke-bundle-delivery.ps1" -Message "Bundle delivery job should call the committed delivery entrypoint."
    Assert-TextContains -Text $promotionJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Bundle promotion job should call the committed workstation validator."
    Assert-TextContains -Text $promotionJenkinsfile -Expected "scripts\\invoke-bundle-promotion.ps1" -Message "Bundle promotion job should call the committed promotion entrypoint."

    foreach ($jenkinsfile in @($repositoryJenkinsfile, $deliveryJenkinsfile, $promotionJenkinsfile, $seedJenkinsfile)) {
        Assert-TextNotMatch -Text $jenkinsfile -Pattern '\&\s+\$scriptPath\s+@\(\$arguments\.ToArray\(\)\)' -Message "Jenkinsfiles should splat named runtime arguments through an intermediate array variable."
        Assert-TextContains -Text $jenkinsfile -Expected '& $scriptPath @argumentArray' -Message "Jenkinsfiles should splat the runtime argument array when invoking PowerShell scripts."
    }

    Assert-RepoRelativeFileExists -Root $Root -Path "config/helm-releases.psd1" -Description "Default Helm release catalog" | Out-Null
    Assert-RepoRelativeFileExists -Root $Root -Path "config/platform-values.env.example" -Description "Default platform values example" | Out-Null

    foreach ($preset in @($Presets)) {
        $presetPath = Join-Path $Root ("config/environments/{0}.psd1" -f $preset)
        Assert-Condition -Condition (Test-Path -Path $presetPath -PathType Leaf) -Message ("Preset file should exist: {0}" -f $presetPath)
        $presetData = Import-PowerShellDataFile -Path $presetPath
        if ($presetData.ContainsKey("ValuesFile")) {
            Assert-RepoRelativeFileExists `
                -Root $Root `
                -Path ([string]$presetData.ValuesFile) `
                -Description ("ValuesFile for preset {0}" -f $preset) | Out-Null
        }
    }
}

function Initialize-JenkinsValidationContext {
    param(
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot,

        [string[]]$RequestedPresets = @(),

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [string]$MissingPresetMessage = "At least one public-safe environment preset should exist."
    )

    $root = Resolve-RepoRoot -RepoRoot $RepoRoot -DefaultRoot $DefaultRoot
    $paths = Get-JenkinsValidationPaths -Root $root
    $presets = @(Get-PresetNames -Root $root -RequestedPresets $RequestedPresets)

    Assert-Condition -Condition ($presets.Count -gt 0) -Message $MissingPresetMessage
    Assert-JenkinsRuntimeContract -Root $root -Paths $paths -Presets $presets

    $resolvedOutputDirectory = Resolve-RepoOutputPath -RepoRoot $root -Path $OutputDirectory
    New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null

    $servicePlan = Invoke-JsonScript -ScriptPath $paths.ServicePlanScript -Arguments @{
        RepoRoot = $root
        Format = "json"
    }
    Assert-ServicePipelinePlan -Plan $servicePlan

    $serviceIndex = @{}
    foreach ($service in @($servicePlan.Services)) {
        $serviceIndex[[string]$service.Name] = $service
    }

    return [PSCustomObject]@{
        Root = $root
        Paths = $paths
        Presets = @($presets)
        OutputDirectory = $resolvedOutputDirectory
        ServicePlan = $servicePlan
        ServiceIndex = $serviceIndex
    }
}

function Get-JenkinsPlanPipelineJob {
    param(
        [object]$Selection,
        [string]$Name
    )

    $jobs = @($Selection.PipelineJobs | Where-Object { [string]$_.Name -eq $Name })
    Assert-Equal `
        -Actual $jobs.Count `
        -Expected 1 `
        -Message ("Selection {0} should include exactly one {1} job" -f $Selection.Name, $Name)

    return $jobs[0]
}

function Assert-JenkinsPlanPipelineJob {
    param(
        [object]$Selection,
        [string]$JobName,
        [string]$ExpectedPath,
        [string]$ExpectedJenkinsfile,
        [string[]]$ExpectedKeyParameters
    )

    $job = Get-JenkinsPlanPipelineJob -Selection $Selection -Name $JobName
    Assert-Equal `
        -Actual ([string]$job.Path) `
        -Expected $ExpectedPath `
        -Message ("{0} path" -f $ExpectedPath)
    Assert-Equal `
        -Actual ([string]$job.Jenkinsfile) `
        -Expected $ExpectedJenkinsfile `
        -Message ("{0} Jenkinsfile" -f $ExpectedPath)

    foreach ($parameter in @($ExpectedKeyParameters)) {
        Assert-ContainsItem `
            -Values @($job.KeyParameters) `
            -Expected $parameter `
            -Message ("{0} is missing key parameter {1}." -f $ExpectedPath, $parameter)
    }
}

function Assert-JenkinsPresetJobPlan {
    param(
        [object]$Plan,
        [string]$Preset,
        [hashtable]$ServiceIndex
    )

    Assert-Equal `
        -Actual ([int]$Plan.SelectionCount) `
        -Expected 1 `
        -Message ("Preset {0} should produce exactly one bundle selection" -f $Preset)

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal `
        -Actual ([string]$selection.Name) `
        -Expected $Preset `
        -Message ("Preset {0} selection name" -f $Preset)
    Assert-Condition `
        -Condition ([bool]$selection.UsesPreset) `
        -Message ("Preset {0} should be marked as a preset-backed selection." -f $Preset)

    $expectedRoot = "platform/{0}" -f $Preset
    Assert-Equal `
        -Actual ([string]$selection.BundleFolderPath) `
        -Expected $expectedRoot `
        -Message ("Preset {0} bundle folder path" -f $Preset)

    Assert-JenkinsPlanPipelineJob `
        -Selection $selection `
        -JobName "repository-validation" `
        -ExpectedPath ("{0}/repository-validation" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\repository-validation.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("VALIDATION_ENVIRONMENT_PRESET={0}" -f $Preset),
            "VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY=false"
        )

    Assert-JenkinsPlanPipelineJob `
        -Selection $selection `
        -JobName "bundle-delivery" `
        -ExpectedPath ("{0}/bundle-delivery" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\bundle-delivery.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("BUNDLE_ENVIRONMENT_PRESET={0}" -f $Preset),
            "BUNDLE_DEPLOY=false"
        )

    Assert-JenkinsPlanPipelineJob `
        -Selection $selection `
        -JobName "bundle-promotion" `
        -ExpectedPath ("{0}/bundle-promotion" -f $expectedRoot) `
        -ExpectedJenkinsfile "jenkins\bundle-promotion.Jenkinsfile" `
        -ExpectedKeyParameters @(
            ("PROMOTION_ENVIRONMENT_PRESET={0}" -f $Preset),
            "PROMOTION_DEPLOY=false",
            "PROMOTION_DEPLOY_DRY_RUN=true"
        )

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-Equal `
        -Actual ([string]$selection.ValidationJobPath) `
        -Expected ("{0}/repository-validation" -f $expectedRoot) `
        -Message ("Preset {0} validation job path field" -f $Preset)
    Assert-Equal `
        -Actual ([string]$selection.DeliveryJobPath) `
        -Expected ("{0}/bundle-delivery" -f $expectedRoot) `
        -Message ("Preset {0} delivery job path field" -f $Preset)
    Assert-Equal `
        -Actual ([string]$selection.PromotionJobPath) `
        -Expected ("{0}/bundle-promotion" -f $expectedRoot) `
        -Message ("Preset {0} promotion job path field" -f $Preset)
    Assert-Equal `
        -Actual @($validationJob.UpstreamDependencies).Count `
        -Expected 0 `
        -Message ("Preset {0} validation job dependency count" -f $Preset)
    Assert-ContainsItem `
        -Values @($deliveryJob.UpstreamDependencies) `
        -Expected ([string]$selection.ValidationJobPath) `
        -Message ("Preset {0} delivery should depend on repository validation." -f $Preset)
    Assert-ContainsItem `
        -Values @($promotionJob.UpstreamDependencies) `
        -Expected ([string]$selection.DeliveryJobPath) `
        -Message ("Preset {0} promotion should depend on bundle delivery." -f $Preset)

    $expectedServiceJobNames = @(
        @($selection.ServiceDirectories) |
            Where-Object { $ServiceIndex.ContainsKey([string]$_) -and [bool]$ServiceIndex[[string]$_].HasJenkinsfile } |
            Sort-Object -Unique
    )
    Assert-Equal `
        -Actual ([int]$Plan.ServiceJobCount) `
        -Expected $expectedServiceJobNames.Count `
        -Message ("Preset {0} service job count should match Jenkinsfile-backed selected services" -f $Preset)

    foreach ($serviceDirectory in @($selection.ServiceDirectories)) {
        Assert-Condition `
            -Condition $ServiceIndex.ContainsKey([string]$serviceDirectory) `
            -Message ("Preset {0} selected service {1} should exist in the service pipeline plan." -f $Preset, $serviceDirectory)
    }

    foreach ($serviceName in $expectedServiceJobNames) {
        $serviceJob = $Plan.ServiceJobs | Where-Object { [string]$_.Name -eq [string]$serviceName } | Select-Object -First 1
        Assert-Condition `
            -Condition ($null -ne $serviceJob) `
            -Message ("Preset {0} should include a service job for {1}." -f $Preset, $serviceName)
        Assert-Equal `
            -Actual ([string]$serviceJob.Path) `
            -Expected ("services/{0}" -f $serviceName) `
            -Message ("Preset {0} service job path for {1}" -f $Preset, $serviceName)
        Assert-Equal `
            -Actual ([string]$serviceJob.Jenkinsfile) `
            -Expected ("services\{0}\Jenkinsfile" -f $serviceName) `
            -Message ("Preset {0} service Jenkinsfile path for {1}" -f $Preset, $serviceName)
        Assert-ContainsItem `
            -Values @($serviceJob.UsedBySelections) `
            -Expected ([string]$Preset) `
            -Message ("Preset {0} service job for {1} should record preset usage." -f $Preset, $serviceName)
    }

    Assert-Condition `
        -Condition (@(@($selection.RecommendedFlow) -match "manual approval").Count -gt 0) `
        -Message ("Preset {0} should keep promotion behind manual approval guidance." -f $Preset)
}

function Assert-ServicePipelinePlan {
    param(
        [object]$Plan
    )

    Assert-Condition `
        -Condition (@($Plan.Services).Count -gt 0) `
        -Message "Service pipeline plan should include at least one catalog service."

    foreach ($service in @($Plan.Services)) {
        Assert-Condition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Name)) `
            -Message "Service pipeline plan contains a service without a name."
        Assert-Condition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.Category)) `
            -Message ("Service {0} is missing a category." -f $service.Name)
        Assert-Condition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.ImageName)) `
            -Message ("Service {0} is missing an image name." -f $service.Name)
        Assert-Condition `
            -Condition ($null -ne $service.HasJenkinsfile) `
            -Message ("Service {0} is missing HasJenkinsfile metadata." -f $service.Name)
        Assert-Condition `
            -Condition (@($service.RequiredFiles).Count -gt 0) `
            -Message ("Service {0} should declare required files." -f $service.Name)

        if (-not [bool]$service.HasJenkinsfile) {
            Assert-Equal `
                -Actual @($service.RequiredJenkinsStrings).Count `
                -Expected 0 `
                -Message ("Service {0} without a Jenkinsfile should not require Jenkinsfile text assertions" -f $service.Name)
        }
    }
}

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

function Assert-JenkinsServiceJobFixturePlan {
    param(
        [object]$Plan
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Service job fixture should produce one bundle selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 1 -Message "Service job fixture should produce one Jenkinsfile-backed service job"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "service-job-fixture" -Message "Service job fixture selection name"
    Assert-ContainsItem -Values @($selection.ServiceDirectories) -Expected "nginx-web" -Message "Service job fixture should select nginx-web"

    $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq "nginx-web" })
    Assert-Equal -Actual $serviceJobs.Count -Expected 1 -Message "Service job fixture should include exactly one nginx-web service job"

    $serviceJob = $serviceJobs[0]
    Assert-Equal -Actual ([string]$serviceJob.Path) -Expected "services/nginx-web" -Message "Service job fixture path"
    Assert-Equal -Actual ([string]$serviceJob.Jenkinsfile) -Expected "services\nginx-web\Jenkinsfile" -Message "Service job fixture Jenkinsfile path"
    Assert-ContainsItem -Values @($serviceJob.RequiredEnvironmentVariables) -Expected "DOCKER_REGISTRY" -Message "Service job fixture should expose registry requirement"
    Assert-ContainsItem -Values @($serviceJob.OptionalEnvironmentVariables) -Expected "CACHE" -Message "Service job fixture should expose optional service variables"
    Assert-ContainsItem -Values @($serviceJob.UsedBySelections) -Expected "service-job-fixture" -Message "Service job fixture should record selection usage"
}

function Assert-MissingServiceJenkinsfileValidationFails {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $Root -OutputDirectory $OutputDirectory -Name "missing-service-jenkinsfile-fixture-repo"
    Remove-Item -Path (Join-Path $fixtureRoot "services/nginx-web/Jenkinsfile") -Force

    $validationScript = Join-Path $fixtureRoot "scripts/validate-service-pipelines.ps1"
    $failed = $false
    $message = ""

    try {
        & $validationScript -RepoRoot $fixtureRoot 6>$null | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    Assert-Condition -Condition $failed -Message "Service pipeline validation should fail when a Jenkinsfile-backed service is missing services/<name>/Jenkinsfile."
    Assert-TextContains -Text $message -Expected "expects a Jenkinsfile-backed service" -Message "Missing Jenkinsfile failure should explain the catalog/service mismatch."
}

function Assert-GeneratedDsl {
    param(
        [string]$DslPath,
        [object]$Plan,
        [string]$Preset
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated DSL should exist for preset {0}: {1}" -f $Preset, $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "// Generated by scripts/export-jenkins-job-dsl.ps1." -Message ("Preset {0} DSL should include the deterministic generator header" -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "Generated by scripts/export-jenkins-job-dsl\.ps1 on [0-9]{4}-[0-9]{2}-[0-9]{2}T" -Message ("Preset {0} DSL should not include a volatile generation timestamp" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message ("Preset {0} DSL should keep the SCM URL parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Message ("Preset {0} DSL should keep the branch spec parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Message ("Preset {0} DSL should keep credentials unset by default" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message ("Preset {0} DSL should use the credentials parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message ("Preset {0} DSL should use the branch parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "lightweight(useLightweightCheckout)" -Message ("Preset {0} DSL should expose lightweight checkout as a parameter" -f $Preset)

    Assert-TextNotMatch -Text $dsl -Pattern "https?://|git@" -Message ("Generated Job DSL for {0} contains a concrete SCM URL." -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message ("Generated Job DSL for {0} contains an inline credentials ID instead of the scmCredentialsId parameter." -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message ("Generated Job DSL for {0} contains an inline branch spec instead of the branchSpec parameter." -f $Preset)

    foreach ($selection in @($Plan.Selections)) {
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Preset {0} DSL should include job {1}" -f $Preset, $job.Path)
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Preset {0} DSL should include Jenkinsfile {1}" -f $Preset, $job.Jenkinsfile)
        }
    }

    foreach ($serviceJob in @($Plan.ServiceJobs)) {
        Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $serviceJob.Path) -Message ("Preset {0} DSL should include service job {1}" -f $Preset, $serviceJob.Path)
        Assert-TextContains -Text $dsl -Expected ([string]$serviceJob.Jenkinsfile).Replace("\", "/") -Message ("Preset {0} DSL should include service Jenkinsfile {1}" -f $Preset, $serviceJob.Jenkinsfile)
    }
}

function Assert-ExplicitScmDsl {
    param(
        [string]$DslPath
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated explicit-SCM DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'git@example.invalid:org/repo.git'" -Message "Explicit SCM URL should be emitted as a Git scp-like repository path."
    Assert-TextContains -Text $dsl -Expected "String branchSpec = '*/feature/quote\'safe'" -Message "Explicit branch spec should be escaped in the generated DSL."
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = 'jenkins-scm\'credentials'" -Message "Explicit credentials ID should be escaped in the generated DSL."
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message "Explicit SCM DSL should keep credentials parameterized."
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message "Explicit SCM DSL should keep branch selection parameterized."

    Assert-Condition -Condition (-not $dsl.Contains("String repoUrl = 'example.invalid/org/repo'with-quote.git'")) -Message "Explicit SCM URL should not be written from an unsafe local-style path fixture."
    Assert-Condition -Condition (-not $dsl.Contains("String branchSpec = '*/feature/quote'safe'")) -Message "Explicit branch spec should not be written without Groovy escaping."
    Assert-Condition -Condition (-not $dsl.Contains("String scmCredentialsId = 'jenkins-scm'credentials'")) -Message "Explicit credentials ID should not be written without Groovy escaping."
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message "Explicit SCM DSL should not inline credentials calls."
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message "Explicit SCM DSL should not inline branch calls."
}

function Assert-JobDslScmInputValidation {
    param(
        [string]$ScriptPath,
        [string]$Root,
        [string]$OutputDirectory,
        [string]$Preset
    )

    $cases = @(
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                RepoUrl = "https://user:token@example.invalid/org/repo.git"
                OutputPath = (Join-Path $OutputDirectory "unsafe-embedded-scm-credentials.groovy")
            }
            ExpectedMessage = "RepoUrl must not include embedded credentials"
            Message = "Job DSL export should reject repository URLs with embedded credentials."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                RepoUrl = "file:///tmp/private-repo.git"
                OutputPath = (Join-Path $OutputDirectory "unsafe-local-scm-uri.groovy")
            }
            ExpectedMessage = "RepoUrl scheme must be one of https, ssh, or git+ssh."
            Message = "Job DSL export should reject local file repository URLs."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                RepoUrl = "ssh:///org/repo.git"
                OutputPath = (Join-Path $OutputDirectory "unsafe-missing-scm-host.groovy")
            }
            ExpectedMessage = "RepoUrl absolute URIs must include a host."
            Message = "Job DSL export should reject repository URLs without a host."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                RepoUrl = "example.invalid/org/repo.git"
                OutputPath = (Join-Path $OutputDirectory "unsafe-relative-scm-path.groovy")
            }
            ExpectedMessage = "RepoUrl must be an HTTPS/SSH absolute URI or a Git scp-like repository path."
            Message = "Job DSL export should reject relative or local-style repository paths."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                RepoUrl = "https://example.invalid/org/repo.git`nbranch('main')"
                OutputPath = (Join-Path $OutputDirectory "unsafe-repo-url-control-character.groovy")
            }
            ExpectedMessage = "RepoUrl must not contain control characters."
            Message = "Job DSL export should reject repository URLs with control characters."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                BranchSpec = "*/feature/safe`n*/main"
                OutputPath = (Join-Path $OutputDirectory "unsafe-branch-spec-control-character.groovy")
            }
            ExpectedMessage = "BranchSpec must not contain control characters."
            Message = "Job DSL export should reject branch specs with control characters."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                ScmCredentialsId = "jenkins-scm`ncredential"
                OutputPath = (Join-Path $OutputDirectory "unsafe-scm-credentials-control-character.groovy")
            }
            ExpectedMessage = "ScmCredentialsId must not contain control characters."
            Message = "Job DSL export should reject SCM credentials IDs with control characters."
        }
    )

    foreach ($case in $cases) {
        $failed = $false
        $failureMessage = ""
        $arguments = $case.Arguments

        try {
            & $ScriptPath @arguments 6>$null | Out-Null
        }
        catch {
            $failed = $true
            $failureMessage = [string]$_
        }

        Assert-Condition -Condition $failed -Message ([string]$case.Message)
        Assert-TextContains -Text $failureMessage -Expected ([string]$case.ExpectedMessage) -Message ("Failure should explain rejected SCM input: {0}" -f $case.ExpectedMessage)
    }
}

function Assert-SeedJobSafety {
    param(
        [string]$SeedJobPath
    )

    Assert-Condition -Condition (Test-Path -Path $SeedJobPath -PathType Leaf) -Message ("Seed Jenkinsfile should exist: {0}" -f $SeedJobPath)
    $seedJob = Get-Content -Path $SeedJobPath -Raw

    Assert-TextContains -Text $seedJob -Expected "SEED_CONFIRM_REMOVED_JOB_DELETE" -Message "Seed job should expose a delete confirmation parameter."
    Assert-TextContains -Text $seedJob -Expected "SEED_REMOVED_JOB_ACTION -eq 'DELETE'" -Message "Seed job should check destructive removed-job action."
    Assert-TextContains -Text $seedJob -Expected "SEED_CONFIRM_REMOVED_JOB_DELETE must be true before applying Job DSL with SEED_REMOVED_JOB_ACTION=DELETE." -Message "Seed job should fail before destructive delete without confirmation."
    Assert-TextContains -Text $seedJob -Expected "Assert-ConcreteScmParameter -Name 'SEED_REPO_URL'" -Message "Seed job should require a concrete SCM URL before applying Job DSL."
    Assert-TextContains -Text $seedJob -Expected "Assert-ConcreteScmParameter -Name 'SEED_BRANCH_SPEC'" -Message "Seed job should require a concrete branch spec before applying Job DSL."
    Assert-TextContains -Text $seedJob -Expected "DisallowedValues @('REPLACE_WITH_REPOSITORY_URL')" -Message "Seed job should reject the public-safe repository URL placeholder before applying Job DSL."
    Assert-TextContains -Text $seedJob -Expected "DisallowedValues @('REPLACE_WITH_BRANCH_SPEC')" -Message "Seed job should reject the public-safe branch spec placeholder before applying Job DSL."
    Assert-TextContains -Text $seedJob -Expected "must be set before SEED_APPLY_JOB_DSL=true." -Message "Seed job should fail closed when required SCM fields are blank."
    Assert-TextContains -Text $seedJob -Expected "must be changed from its public-safe placeholder before SEED_APPLY_JOB_DSL=true." -Message "Seed job should fail closed when SCM placeholders are still present."
}

function Assert-JenkinsfileArtifactPathSafety {
    param(
        [string]$JenkinsfilePath,
        [string[]]$ExpectedParameterNames,
        [string[]]$ExpectedDirectoryParameterNames = @(),
        [string[]]$ExpectedPipelineBoundaryNames = @()
    )

    Assert-Condition -Condition (Test-Path -Path $JenkinsfilePath -PathType Leaf) -Message ("Jenkinsfile should exist: {0}" -f $JenkinsfilePath)
    $jenkinsfile = Get-Content -Path $JenkinsfilePath -Raw

    Assert-TextContains -Text $jenkinsfile -Expected "String requireLiteralOutPath" -Message ("{0} should validate literal out/ artifact paths" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "must stay under out/." -Message ("{0} should require archive paths under out/" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "must be a literal path, not an Ant glob pattern." -Message ("{0} should reject archive glob patterns" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "segment == '..'" -Message ("{0} should reject parent-directory archive segments" -f $JenkinsfilePath)

    if (@($ExpectedDirectoryParameterNames).Count -gt 0) {
        Assert-TextContains -Text $jenkinsfile -Expected "String requireLiteralOutDirectoryPattern" -Message ("{0} should sanitize directory archive patterns" -f $JenkinsfilePath)
    }

    foreach ($parameterName in @($ExpectedParameterNames)) {
        Assert-TextContains `
            -Text $jenkinsfile `
            -Expected ("requireLiteralOutPath(params.{0}, '{0}')" -f $parameterName) `
            -Message ("{0} should sanitize {1} before archiving" -f $JenkinsfilePath, $parameterName)
    }

    foreach ($parameterName in @($ExpectedDirectoryParameterNames)) {
        Assert-TextContains `
            -Text $jenkinsfile `
            -Expected ("requireLiteralOutDirectoryPattern(params.{0}, '{0}')" -f $parameterName) `
            -Message ("{0} should sanitize {1}" -f $JenkinsfilePath, $parameterName)
    }

    foreach ($parameterName in @($ExpectedPipelineBoundaryNames)) {
        Assert-TextContains `
            -Text $jenkinsfile `
            -Expected ("Assert-LiteralOutPath -Name '{0}'" -f $parameterName) `
            -Message ("{0} should validate {1} before invoking downstream scripts" -f $JenkinsfilePath, $parameterName)
    }
}

function Assert-JenkinsfileDeploymentApprovalSafety {
    param(
        [string]$JenkinsfilePath,
        [string]$DeployParameterName,
        [string]$DryRunParameterName,
        [string]$RequireSecretsParameterName,
        [string]$RequireStatusParameterName
    )

    Assert-Condition -Condition (Test-Path -Path $JenkinsfilePath -PathType Leaf) -Message ("Jenkinsfile should exist: {0}" -f $JenkinsfilePath)
    $jenkinsfile = Get-Content -Path $JenkinsfilePath -Raw

    Assert-TextContains -Text $jenkinsfile -Expected ("booleanParam(name: '{0}', defaultValue: false" -f $DeployParameterName) -Message ("{0} should keep deployment opt-in disabled by default" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected ("booleanParam(name: '{0}', defaultValue: true" -f $DryRunParameterName) -Message ("{0} should keep deployment dry-run enabled by default" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected ("params.{0} && !params.{1}" -f $DeployParameterName, $DryRunParameterName) -Message ("{0} should gate approval on non-dry-run deployment" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "input message:" -Message ("{0} should require Jenkins input approval for non-dry-run deployment" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected ("{0} must be true for non-dry-run deployments." -f $RequireSecretsParameterName) -Message ("{0} should require bootstrap secret readiness before non-dry-run deployment" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected ("{0} must be true for non-dry-run deployments." -f $RequireStatusParameterName) -Message ("{0} should require bootstrap status validation before non-dry-run deployment" -f $JenkinsfilePath)
}
