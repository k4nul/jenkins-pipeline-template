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
