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

function Assert-GeneratedDsl {
    param(
        [string]$DslPath,
        [object]$Plan,
        [string]$Preset
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated DSL should exist for preset {0}: {1}" -f $Preset, $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

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

    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'example.invalid/org/repo\'with-quote.git'" -Message "Explicit SCM URL should be escaped in the generated DSL."
    Assert-TextContains -Text $dsl -Expected "String branchSpec = '*/feature/quote\'safe'" -Message "Explicit branch spec should be escaped in the generated DSL."
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = 'jenkins-scm\'credentials'" -Message "Explicit credentials ID should be escaped in the generated DSL."
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message "Explicit SCM DSL should keep credentials parameterized."
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message "Explicit SCM DSL should keep branch selection parameterized."

    Assert-Condition -Condition (-not $dsl.Contains("String repoUrl = 'example.invalid/org/repo'with-quote.git'")) -Message "Explicit SCM URL should not be written without Groovy escaping."
    Assert-Condition -Condition (-not $dsl.Contains("String branchSpec = '*/feature/quote'safe'")) -Message "Explicit branch spec should not be written without Groovy escaping."
    Assert-Condition -Condition (-not $dsl.Contains("String scmCredentialsId = 'jenkins-scm'credentials'")) -Message "Explicit credentials ID should not be written without Groovy escaping."
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message "Explicit SCM DSL should not inline credentials calls."
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message "Explicit SCM DSL should not inline branch calls."
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
