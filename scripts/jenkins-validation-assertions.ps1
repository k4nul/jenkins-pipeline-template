# Shared assertions for Jenkins Job DSL validation and public preset tests.

. (Join-Path -Path $PSScriptRoot -ChildPath "jenkins-validation-fixtures.ps1")

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
        DependencyInventoryScript = Join-Path $Root "scripts/show-dependency-inventory.ps1"
        JobDslScript = Join-Path $Root "scripts/export-jenkins-job-dsl.ps1"
        ServiceValidationScript = Join-Path $Root "scripts/validate-service-pipelines.ps1"
        WorkstationValidationScript = Join-Path $Root "scripts/validate-workstation.ps1"
        RepositoryValidationScript = Join-Path $Root "scripts/invoke-repository-validation.ps1"
        BundleDeliveryScript = Join-Path $Root "scripts/invoke-bundle-delivery.ps1"
        BundlePromotionScript = Join-Path $Root "scripts/invoke-bundle-promotion.ps1"
        PhaseValidationScript = Join-Path $Root "scripts/run-phase-validation.sh"
        PublicPresetTestScript = Join-Path $Root "tests/jenkins-job-dsl.public-presets.ps1"
        PhaseGateManifest = Join-Path $Root "docs/instructions/phase-gates.json"
        PhaseValidationWorkflow = Join-Path $Root ".github/workflows/phase-validation.yml"
        TestingGuide = Join-Path $Root "docs/testing.md"
        TroubleshootingGuide = Join-Path $Root "docs/troubleshooting.md"
        PhaseHandoff = Join-Path $Root "docs/phase-handoff.md"
        HelmConfigFile = Join-Path $Root "config/helm-releases.psd1"
        KubernetesControllerDeployment = Join-Path $Root "k8s/jenkins-controller/jenkins.yaml"
        KubernetesControllerReadme = Join-Path $Root "k8s/jenkins-controller/README.md"
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

function Assert-RepoOutputPathCaseBoundary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $failed = $false
    $message = ""
    try {
        Resolve-RepoOutputPath -RepoRoot $Root -Path "OUT/jenkins/case-boundary-probe.txt" | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    Assert-Condition -Condition $failed -Message "Repo output path validation should reject case-variant output roots."
    Assert-TextContains -Text $message -Expected "OutputPath must resolve under the repository out directory" -Message "Case-variant output root rejection should explain the repository out boundary."
}

function Assert-RepoOutputPathRejectsControlCharacters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $failed = $false
    $message = ""
    try {
        Resolve-RepoOutputPath -RepoRoot $Root -Path "out/jenkins/control`ncharacter.txt" | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    Assert-Condition -Condition $failed -Message "Repo output path validation should reject control characters."
    Assert-TextContains -Text $message -Expected "OutputPath must not contain control characters" -Message "Control-character output path rejection should explain the unsafe input."
}

function Assert-RepoOutputPathRejectsReparsePointSegments {
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
        Write-Information -MessageData ("Skipping OutputPath symlink boundary assertion because symbolic links are unavailable: {0}" -f [string]$_) -InformationAction Continue
        return
    }

    try {
        $failed = $false
        $message = ""
        $probePath = [System.IO.Path]::GetRelativePath($Root, (Join-Path -Path $linkPath -ChildPath "probe.txt"))
        try {
            Resolve-RepoOutputPath -RepoRoot $Root -Path $probePath | Out-Null
        }
        catch {
            $failed = $true
            $message = [string]$_
        }

        Assert-Condition -Condition $failed -Message "Repo output path validation should reject symlink or reparse-point path segments."
        Assert-TextContains -Text $message -Expected "OutputPath must not traverse symlink or reparse-point paths" -Message "Symlink output path rejection should explain the repository out boundary."
    }
    finally {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
        }
    }
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
        $Paths.DependencyInventoryScript,
        $Paths.RepositoryValidationScript,
        $Paths.BundleDeliveryScript,
        $Paths.BundlePromotionScript,
        $Paths.PublicPresetTestScript
    )) {
        Assert-Condition -Condition (Test-Path -Path $scriptPath -PathType Leaf) -Message ("Jenkins runtime contract file should exist: {0}" -f $scriptPath)
    }

    Assert-Condition -Condition (Test-Path -Path $Paths.HelmConfigFile -PathType Leaf) -Message ("Public-safe Helm release catalog should exist: {0}" -f $Paths.HelmConfigFile)
    Assert-Condition -Condition (Test-Path -Path $Paths.KubernetesControllerDeployment -PathType Leaf) -Message ("Public-safe Jenkins controller deployment should exist: {0}" -f $Paths.KubernetesControllerDeployment)
    Assert-Condition -Condition (Test-Path -Path $Paths.KubernetesControllerReadme -PathType Leaf) -Message ("Public-safe Jenkins controller README should exist: {0}" -f $Paths.KubernetesControllerReadme)

    $repositoryJenkinsfile = Get-Content -Path $Paths.RepositoryJobPath -Raw
    $deliveryJenkinsfile = Get-Content -Path $Paths.DeliveryJobPath -Raw
    $promotionJenkinsfile = Get-Content -Path $Paths.PromotionJobPath -Raw
    $seedJenkinsfile = Get-Content -Path $Paths.SeedJobPath -Raw
    $controllerDeployment = Get-Content -Path $Paths.KubernetesControllerDeployment -Raw
    $controllerReadme = Get-Content -Path $Paths.KubernetesControllerReadme -Raw

    Assert-TextContains -Text $repositoryJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Repository validation job should call the committed workstation validator."
    Assert-TextContains -Text $repositoryJenkinsfile -Expected "scripts\\invoke-repository-validation.ps1" -Message "Repository validation job should call the committed repository validation entrypoint."
    Assert-TextContains -Text $deliveryJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Bundle delivery job should call the committed workstation validator."
    Assert-TextContains -Text $deliveryJenkinsfile -Expected "scripts\\invoke-bundle-delivery.ps1" -Message "Bundle delivery job should call the committed delivery entrypoint."
    Assert-TextContains -Text $promotionJenkinsfile -Expected "scripts\\validate-workstation.ps1" -Message "Bundle promotion job should call the committed workstation validator."
    Assert-TextContains -Text $promotionJenkinsfile -Expected "scripts\\invoke-bundle-promotion.ps1" -Message "Bundle promotion job should call the committed promotion entrypoint."
    Assert-TextContains -Text $controllerDeployment -Expected "runAsNonRoot: true" -Message "Jenkins controller example should keep a non-root pod security default."
    Assert-TextContains -Text $controllerDeployment -Expected "runAsUser: 1000" -Message "Jenkins controller example should run as the Jenkins image user."
    Assert-TextContains -Text $controllerDeployment -Expected "runAsGroup: 1000" -Message "Jenkins controller example should run as the Jenkins image group."
    Assert-TextContains -Text $controllerDeployment -Expected "fsGroup: 1000" -Message "Jenkins controller example should keep Jenkins volume ownership explicit."
    Assert-TextContains -Text $controllerDeployment -Expected "allowPrivilegeEscalation: false" -Message "Jenkins controller example should disable privilege escalation."
    Assert-TextContains -Text $controllerDeployment -Expected "drop:" -Message "Jenkins controller example should drop Linux capabilities."
    Assert-TextContains -Text $controllerDeployment -Expected "type: RuntimeDefault" -Message "Jenkins controller example should request the runtime default seccomp profile."
    Assert-TextContains -Text $controllerReadme -Expected "non-root pod/container security defaults" -Message "Jenkins controller README should document the sample security defaults."

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

function Assert-PhaseValidationEvidenceContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    $expectedCommand = "sh scripts/run-phase-validation.sh"

    foreach ($path in @(
        $Paths.PhaseValidationScript,
        $Paths.PhaseGateManifest,
        $Paths.PhaseValidationWorkflow,
        $Paths.TestingGuide,
        $Paths.TroubleshootingGuide,
        $Paths.PhaseHandoff
    )) {
        Assert-Condition -Condition (Test-Path -Path $path -PathType Leaf) -Message ("Phase validation evidence file should exist: {0}" -f $path)
    }

    $manifest = Get-Content -Path $Paths.PhaseGateManifest -Raw | ConvertFrom-Json
    Assert-Equal `
        -Actual ([string]$manifest.transition.validation_command) `
        -Expected $expectedCommand `
        -Message "Phase manifest should keep the wrapper as the canonical validation command"

    $phaseGate = @($manifest.required_gates) | Where-Object { $_.id -eq "phase-validation-passes" } | Select-Object -First 1
    Assert-Condition -Condition ($null -ne $phaseGate) -Message "Phase manifest should define the phase-validation-passes gate."
    Assert-Equal `
        -Actual ([string]$phaseGate.status) `
        -Expected "machine-check" `
        -Message "Phase validation gate should stay machine-checked instead of relying on stale prose evidence"

    $wrapper = Get-Content -Path $Paths.PhaseValidationScript -Raw
    Assert-TextContains -Text $wrapper -Expected "Phase validation failed during" -Message "Phase wrapper should report the first failing labeled step."
    Assert-TextContains -Text $wrapper -Expected "Using PowerShell:" -Message "Phase wrapper should report the resolved PowerShell runtime."
    Assert-TextContains -Text $wrapper -Expected 'run_step "dev Jenkins job plan"' -Message "Phase wrapper should label the dev dashboard job-plan step."
    Assert-TextContains -Text $wrapper -Expected 'run_step "public preset test suite"' -Message "Phase wrapper should label the public preset test step."

    $workflow = Get-Content -Path $Paths.PhaseValidationWorkflow -Raw
    Assert-TextContains -Text $workflow -Expected $expectedCommand -Message "CI workflow should run the same phase validation wrapper."
    Assert-TextContains -Text $workflow -Expected "actions/upload-artifact@v4" -Message "CI workflow should preserve generated validation fixtures as workflow artifacts."
    Assert-TextContains -Text $workflow -Expected "out/jenkins/**" -Message "CI workflow should upload ignored Jenkins validation fixtures only from out/."

    foreach ($docPath in @($Paths.TestingGuide, $Paths.TroubleshootingGuide, $Paths.PhaseHandoff)) {
        $doc = Get-Content -Path $docPath -Raw
        Assert-TextContains -Text $doc -Expected $expectedCommand -Message ("Documentation should reference the canonical wrapper command: {0}" -f $docPath)
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

function Assert-PublicPresetServiceCatalogCoverage {
    param(
        [object]$Selection,
        [object]$Plan,
        [string]$Preset,
        [hashtable]$ServiceIndex
    )

    $serviceDirectories = @(Get-NormalizedList -Values @($Selection.ServiceDirectories))

    foreach ($application in @(Get-NormalizedList -Values @($Selection.Applications))) {
        Assert-ContainsItem `
            -Values $serviceDirectories `
            -Expected $application `
            -Message ("Preset {0} should carry selected application {1} into the service directory projection." -f $Preset, $application)

        Assert-Condition `
            -Condition $ServiceIndex.ContainsKey([string]$application) `
            -Message ("Preset {0} selected application {1} should have service pipeline catalog metadata." -f $Preset, $application)

        $service = $ServiceIndex[[string]$application]
        Assert-Equal `
            -Actual ([string]$service.Category) `
            -Expected "public-image" `
            -Message ("Preset {0} service {1} should remain a public-image catalog entry." -f $Preset, $application)
        Assert-Condition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$service.ImageName)) `
            -Message ("Preset {0} service {1} should declare a public image." -f $Preset, $application)
        Assert-Condition `
            -Condition (@($service.RequiredFiles).Count -gt 0) `
            -Message ("Preset {0} service {1} should declare required service-local files." -f $Preset, $application)
        Assert-Condition `
            -Condition (@($service.ArtifactInputs).Count -gt 0) `
            -Message ("Preset {0} service {1} should document service artifact input guidance." -f $Preset, $application)

        $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq [string]$application })
        if ([bool]$service.HasJenkinsfile) {
            Assert-Equal `
                -Actual $serviceJobs.Count `
                -Expected 1 `
                -Message ("Preset {0} Jenkinsfile-backed service {1} should project one service job." -f $Preset, $application)
        }
        else {
            Assert-Equal `
                -Actual $serviceJobs.Count `
                -Expected 0 `
                -Message ("Preset {0} catalog-only service {1} should not project a Jenkins service job." -f $Preset, $application)
        }
    }
}

function Assert-MultiPresetPlanAndDsl {
    param(
        [object]$Plan,
        [string[]]$ExpectedPresets,
        [string]$DslPath
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected $ExpectedPresets.Count -Message "Multi-preset plan should include every requested preset selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "Current public-safe presets should not create shared service jobs without service Jenkinsfiles"
    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated multi-preset DSL should exist: {0}" -f $DslPath)

    $dsl = Get-Content -Path $DslPath -Raw
    Assert-TextContains -Text $dsl -Expected ("// Selection count: {0}" -f $ExpectedPresets.Count) -Message "Multi-preset DSL should record the combined selection count"
    Assert-TextContains -Text $dsl -Expected "// Service job count: 0" -Message "Multi-preset DSL should record the absence of generated service jobs"
    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message "Multi-preset DSL should keep the SCM URL parameterized"
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Message "Multi-preset DSL should keep the branch spec parameterized"
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Message "Multi-preset DSL should keep credentials unset by default"
    Assert-TextNotMatch -Text $dsl -Pattern "https?://|git@" -Message "Multi-preset DSL should not include concrete SCM URLs"

    foreach ($preset in @($ExpectedPresets)) {
        $selections = @($Plan.Selections | Where-Object { [string]$_.Name -eq $preset })
        Assert-Equal -Actual $selections.Count -Expected 1 -Message ("Multi-preset plan should include selection {0} once" -f $preset)

        $selection = $selections[0]
        Assert-Condition -Condition ([bool]$selection.UsesPreset) -Message ("Selection {0} should remain preset-backed" -f $preset)
        Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected ("platform/{0}" -f $preset) -Message ("Selection {0} should keep its own bundle folder" -f $preset)
        Assert-TextContains -Text $dsl -Expected ("folder('platform/{0}')" -f $preset) -Message ("Multi-preset DSL should include folder for {0}" -f $preset)

        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Multi-preset DSL should include job {0}" -f $job.Path)
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Multi-preset DSL should include Jenkinsfile {0}" -f $job.Jenkinsfile)
        }
    }
}

function Assert-PublicPresetMatrixServiceCoverage {
    param(
        [object]$Plan,
        [string[]]$ExpectedPresets,
        [hashtable]$ServiceIndex
    )

    $expectedPresetNames = @(Get-NormalizedList -Values $ExpectedPresets)
    Assert-Equal `
        -Actual ([int]$Plan.SelectionCount) `
        -Expected $expectedPresetNames.Count `
        -Message "Full public preset matrix should include every expected selection"

    $selectionByName = @{}
    foreach ($selection in @($Plan.Selections)) {
        $selectionByName[[string]$selection.Name] = $selection
    }

    $serviceUsage = @{}
    foreach ($preset in $expectedPresetNames) {
        Assert-Condition `
            -Condition $selectionByName.ContainsKey($preset) `
            -Message ("Full public preset matrix should include selection {0}." -f $preset)

        $selection = $selectionByName[$preset]
        Assert-Condition `
            -Condition ([bool]$selection.UsesPreset) `
            -Message ("Full public preset matrix selection {0} should remain preset-backed." -f $preset)

        Assert-PublicPresetServiceCatalogCoverage `
            -Selection $selection `
            -Plan $Plan `
            -Preset $preset `
            -ServiceIndex $ServiceIndex

        foreach ($serviceDirectory in @(Get-NormalizedList -Values @($selection.ServiceDirectories))) {
            if (-not $serviceUsage.ContainsKey($serviceDirectory)) {
                $serviceUsage[$serviceDirectory] = [System.Collections.Generic.List[string]]::new()
            }

            if (-not $serviceUsage[$serviceDirectory].Contains($preset)) {
                $serviceUsage[$serviceDirectory].Add($preset) | Out-Null
            }
        }
    }

    $expectedServiceJobNames = @()
    foreach ($serviceName in @($serviceUsage.Keys | Sort-Object)) {
        Assert-Condition `
            -Condition $ServiceIndex.ContainsKey([string]$serviceName) `
            -Message ("Full public preset matrix selected service {0} should have catalog metadata." -f $serviceName)

        $service = $ServiceIndex[[string]$serviceName]
        Assert-Equal `
            -Actual ([string]$service.Category) `
            -Expected "public-image" `
            -Message ("Full public preset matrix service {0} should remain public-image metadata." -f $serviceName)

        $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq [string]$serviceName })
        if ([bool]$service.HasJenkinsfile) {
            $expectedServiceJobNames += [string]$serviceName
            Assert-Equal `
                -Actual $serviceJobs.Count `
                -Expected 1 `
                -Message ("Full public preset matrix Jenkinsfile-backed service {0} should project one shared service job." -f $serviceName)

            $serviceJob = $serviceJobs[0]
            foreach ($usedBySelection in @($serviceUsage[$serviceName].ToArray() | Sort-Object -Unique)) {
                Assert-ContainsItem `
                    -Values @($serviceJob.UsedBySelections) `
                    -Expected ([string]$usedBySelection) `
                    -Message ("Full public preset matrix service job {0} should record usage by {1}." -f $serviceName, $usedBySelection)
            }
        }
        else {
            Assert-Equal `
                -Actual $serviceJobs.Count `
                -Expected 0 `
                -Message ("Full public preset matrix catalog-only service {0} should not project a Jenkins service job." -f $serviceName)
        }
    }

    $expectedServiceJobNames = @($expectedServiceJobNames | Sort-Object -Unique)
    Assert-Equal `
        -Actual ([int]$Plan.ServiceJobCount) `
        -Expected $expectedServiceJobNames.Count `
        -Message "Full public preset matrix service job count should match Jenkinsfile-backed selected services"
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

    $selection = @($Plan.Selections)[0]
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

    Assert-PublicPresetServiceCatalogCoverage `
        -Selection $selection `
        -Plan $Plan `
        -Preset $Preset `
        -ServiceIndex $ServiceIndex

    foreach ($serviceName in $expectedServiceJobNames) {
        $serviceJob = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq [string]$serviceName })[0]
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

function Assert-JenkinsServiceJobFixturePlan {
    param(
        [object]$Plan
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Service job fixture should produce one bundle selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 1 -Message "Service job fixture should produce one Jenkinsfile-backed service job"

    $selection = @($Plan.Selections)[0]
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

function Assert-JenkinsServiceJobSharedPresetPlan {
    param(
        [object]$Plan,
        [string]$ExpectedServiceJobRoot = "services"
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 2 -Message "Shared service job fixture should produce two bundle selections"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 1 -Message "Shared service job fixture should de-duplicate one Jenkinsfile-backed service job"

    $selectionNames = @($Plan.Selections | ForEach-Object { [string]$_.Name } | Sort-Object)
    Assert-ContainsItem -Values $selectionNames -Expected "fixture-alpha" -Message "Shared service fixture should include fixture-alpha"
    Assert-ContainsItem -Values $selectionNames -Expected "fixture-beta" -Message "Shared service fixture should include fixture-beta"

    foreach ($selection in @($Plan.Selections)) {
        Assert-ContainsItem -Values @($selection.ServiceDirectories) -Expected "nginx-web" -Message ("Selection {0} should select nginx-web" -f $selection.Name)

        $expectedRoot = "platform/{0}" -f $selection.Name
        Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected $expectedRoot -Message ("Selection {0} bundle folder path" -f $selection.Name)

        $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
        $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
        $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

        Assert-Equal -Actual ([string]$validationJob.Path) -Expected ("{0}/repository-validation" -f $expectedRoot) -Message ("Selection {0} validation job path" -f $selection.Name)
        Assert-Equal -Actual ([string]$deliveryJob.Path) -Expected ("{0}/bundle-delivery" -f $expectedRoot) -Message ("Selection {0} delivery job path" -f $selection.Name)
        Assert-Equal -Actual ([string]$promotionJob.Path) -Expected ("{0}/bundle-promotion" -f $expectedRoot) -Message ("Selection {0} promotion job path" -f $selection.Name)
        Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message ("Selection {0} delivery should depend on validation" -f $selection.Name)
        Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message ("Selection {0} promotion should depend on delivery" -f $selection.Name)
    }

    $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq "nginx-web" })
    Assert-Equal -Actual $serviceJobs.Count -Expected 1 -Message "Shared service job fixture should include exactly one nginx-web service job"

    $serviceJob = $serviceJobs[0]
    Assert-Equal -Actual ([string]$serviceJob.Path) -Expected ("{0}/nginx-web" -f $ExpectedServiceJobRoot) -Message "Shared service job fixture path"
    Assert-Equal -Actual ([string]$serviceJob.Jenkinsfile) -Expected "services\nginx-web\Jenkinsfile" -Message "Shared service job fixture Jenkinsfile path"
    Assert-ContainsItem -Values @($serviceJob.RequiredEnvironmentVariables) -Expected "DOCKER_REGISTRY" -Message "Shared service job fixture should expose registry requirement"
    Assert-ContainsItem -Values @($serviceJob.OptionalEnvironmentVariables) -Expected "CACHE" -Message "Shared service job fixture should expose optional service variables"
    Assert-ContainsItem -Values @($serviceJob.UsedBySelections) -Expected "fixture-alpha" -Message "Shared service job should record fixture-alpha usage"
    Assert-ContainsItem -Values @($serviceJob.UsedBySelections) -Expected "fixture-beta" -Message "Shared service job should record fixture-beta usage"
}

function Assert-JenkinsServiceJobsSkippedPlan {
    param(
        [object]$Plan
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 2 -Message "Skip-service fixture should still produce two bundle selections"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "SkipServiceJobs should suppress Jenkinsfile-backed service jobs"
    Assert-Equal -Actual (@($Plan.ServiceJobs).Count) -Expected 0 -Message "SkipServiceJobs should leave the service job list empty"

    foreach ($selection in @($Plan.Selections)) {
        Assert-ContainsItem -Values @($selection.ServiceDirectories) -Expected "nginx-web" -Message ("Selection {0} should still record selected service directories" -f $selection.Name)
    }
}

function Assert-MissingServiceJenkinsfileValidationFails {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-MissingServiceJenkinsfileFixtureContext -Root $Root -OutputDirectory $OutputDirectory
    $failed = $false
    $message = ""

    try {
        & $fixture.ServiceValidationScript -RepoRoot $fixture.Root 6>$null | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    Assert-Condition -Condition $failed -Message "Service pipeline validation should fail when a Jenkinsfile-backed service is missing services/<name>/Jenkinsfile."
    Assert-TextContains -Text $message -Expected "expects a Jenkinsfile-backed service" -Message "Missing Jenkinsfile failure should explain the catalog/service mismatch."
}

function Assert-UnsafeServiceCatalogNamesFail {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-UnsafeServiceCatalogFixtureContext -Root $Root -OutputDirectory $OutputDirectory

    foreach ($case in @(Get-UnsafeServiceCatalogNameCases)) {
        Set-Content -Path $fixture.CatalogPath -Value ([string]$case.Catalog) -Encoding utf8NoBOM

        $failed = $false
        $message = ""
        try {
            & $fixture.ServiceValidationScript -RepoRoot $fixture.Root 6>$null | Out-Null
        }
        catch {
            $failed = $true
            $message = [string]$_
        }

        Assert-Condition -Condition $failed -Message ([string]$case.Message)
        Assert-TextContains -Text $message -Expected ([string]$case.ExpectedMessage) -Message ([string]$case.Message)
    }
}

function Assert-UnsupportedServiceComposeUpdateFails {
    param(
        [string]$Root,
        [string]$OutputDirectory
    )

    $fixture = New-UnsupportedServiceComposeUpdateFixtureContext -Root $Root -OutputDirectory $OutputDirectory
    $failed = $false
    $message = ""
    try {
        & $fixture.ServiceValidationScript -RepoRoot $fixture.Root 6>$null | Out-Null
    }
    catch {
        $failed = $true
        $message = [string]$_
    }

    Assert-Condition -Condition $failed -Message "Service pipeline validation should reject unsupported ComposeUpdate catalog values."
    Assert-TextContains -Text $message -Expected "unsupported ComposeUpdate value" -Message "Unsupported ComposeUpdate failure should explain the catalog value mismatch."
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
    Assert-TextContains -Text $dsl -Expected ("// Selection count: {0}" -f ([int]$Plan.SelectionCount)) -Message ("Preset {0} DSL should record the generated selection count." -f $Preset)
    Assert-TextContains -Text $dsl -Expected ("// Service job count: {0}" -f ([int]$Plan.ServiceJobCount)) -Message ("Preset {0} DSL should record the generated service job count." -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message ("Preset {0} DSL should keep the SCM URL parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Message ("Preset {0} DSL should keep the branch spec parameterized" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Message ("Preset {0} DSL should keep credentials unset by default" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "url(repoUrl)" -Message ("Preset {0} DSL should use the repository URL parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message ("Preset {0} DSL should use the credentials parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message ("Preset {0} DSL should use the branch parameter" -f $Preset)
    Assert-TextContains -Text $dsl -Expected "lightweight(useLightweightCheckout)" -Message ("Preset {0} DSL should expose lightweight checkout as a parameter" -f $Preset)

    $jobRoot = ([string]$Plan.JobRoot).Trim()
    $serviceJobRoot = ([string]$Plan.ServiceJobRoot).Trim()
    if ($jobRoot) {
        Assert-TextContains -Text $dsl -Expected ("folder('{0}')" -f $jobRoot) -Message ("Preset {0} DSL should create the plan-owned bundle job root {1}." -f $Preset, $jobRoot)
    }
    if ($serviceJobRoot) {
        Assert-TextContains -Text $dsl -Expected ("folder('{0}')" -f $serviceJobRoot) -Message ("Preset {0} DSL should create the plan-owned service job root {1}." -f $Preset, $serviceJobRoot)
    }

    Assert-TextNotMatch -Text $dsl -Pattern "https?://|git@" -Message ("Generated Job DSL for {0} contains a concrete SCM URL." -f $Preset)
    Assert-TextNotMatch -Text $dsl -Pattern "url\(['""]" -Message ("Generated Job DSL for {0} contains an inline SCM URL instead of the repoUrl parameter." -f $Preset)
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
    Assert-TextContains -Text $dsl -Expected "String branchSpec = '*/feature/quote-safe'" -Message "Explicit branch spec should be emitted as a constrained Jenkins branch spec."
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = 'jenkins-scm-credentials'" -Message "Explicit credentials ID should be emitted as a constrained Jenkins credentials ID."
    Assert-TextContains -Text $dsl -Expected "url(repoUrl)" -Message "Explicit SCM DSL should keep the repository URL parameterized."
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message "Explicit SCM DSL should keep credentials parameterized."
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message "Explicit SCM DSL should keep branch selection parameterized."

    Assert-Condition -Condition (-not $dsl.Contains("String repoUrl = 'example.invalid/org/repo'with-quote.git'")) -Message "Explicit SCM URL should not be written from an unsafe local-style path fixture."
    Assert-Condition -Condition (-not $dsl.Contains("String branchSpec = '*/feature/quote'safe'")) -Message "Explicit branch spec should not allow quoted branch metadata."
    Assert-Condition -Condition (-not $dsl.Contains("String scmCredentialsId = 'jenkins-scm'credentials'")) -Message "Explicit credentials ID should not allow quoted credentials metadata."
    Assert-TextNotMatch -Text $dsl -Pattern "url\(['""]" -Message "Explicit SCM DSL should not inline repository URL calls."
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message "Explicit SCM DSL should not inline credentials calls."
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message "Explicit SCM DSL should not inline branch calls."
}

function Assert-ServiceJobSharedPresetDsl {
    param(
        [object]$Plan,
        [string]$DslPath,
        [string]$ExpectedServiceJobRoot = "services"
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated shared service-job fixture DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "// Selection count: 2" -Message "Shared service-job fixture DSL should record both bundle selections"
    Assert-TextContains -Text $dsl -Expected "// Service job count: 1" -Message "Shared service-job fixture DSL should record one de-duplicated service job"

    foreach ($selection in @($Plan.Selections)) {
        Assert-TextContains -Text $dsl -Expected ("folder('platform/{0}')" -f $selection.Name) -Message ("Shared service-job fixture DSL should include folder for {0}" -f $selection.Name)
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Shared service-job fixture DSL should include bundle job {0}" -f $job.Path)
        }
    }

    $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq "nginx-web" })
    Assert-Equal -Actual $serviceJobs.Count -Expected 1 -Message "Shared service-job DSL assertions require one nginx-web service job"
    $serviceJob = $serviceJobs[0]

    $serviceRootSegments = @($ExpectedServiceJobRoot -split "[/\\]+" | Where-Object { $_ })
    for ($index = 0; $index -lt $serviceRootSegments.Count; $index++) {
        $folderPath = ($serviceRootSegments[0..$index] -join "/")
        Assert-TextContains -Text $dsl -Expected ("folder('{0}')" -f $folderPath) -Message ("Shared service-job fixture DSL should include service root folder {0}" -f $folderPath)
    }

    $serviceJobDeclaration = "pipelineJob('$($serviceJob.Path)')"
    Assert-TextContains -Text $dsl -Expected $serviceJobDeclaration -Message "Shared service-job fixture DSL should include the Jenkinsfile-backed service job once"
    Assert-Equal -Actual ([regex]::Matches($dsl, [regex]::Escape($serviceJobDeclaration)).Count) -Expected 1 -Message "Shared service-job fixture DSL should not duplicate the shared service job"
    Assert-TextContains -Text $dsl -Expected "Used by selections: fixture-alpha, fixture-beta" -Message "Shared service-job fixture DSL should preserve every preset using the service"
    Assert-TextContains -Text $dsl -Expected ([string]$serviceJob.Jenkinsfile).Replace("\", "/") -Message "Shared service-job fixture DSL should include the service Jenkinsfile path"
    Assert-TextNotMatch -Text $dsl -Pattern ("pipelineJob\('{0}/.+'\)" -f ([regex]::Escape([string]$serviceJob.Path))) -Message "Shared service-job fixture DSL should keep one service job at the service root"
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
                BranchSpec = "refs/heads/release candidate"
                OutputPath = (Join-Path $OutputDirectory "unsafe-branch-spec-whitespace.groovy")
            }
            ExpectedMessage = "BranchSpec must not contain whitespace."
            Message = "Job DSL export should reject branch specs with whitespace."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                BranchSpec = "*/feature/quote'safe"
                OutputPath = (Join-Path $OutputDirectory "unsafe-branch-spec-quote.groovy")
            }
            ExpectedMessage = "BranchSpec must contain only letters, digits"
            Message = "Job DSL export should reject branch specs with quoted metadata."
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
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                ScmCredentialsId = "jenkins scm credential"
                OutputPath = (Join-Path $OutputDirectory "unsafe-scm-credentials-whitespace.groovy")
            }
            ExpectedMessage = "ScmCredentialsId must not contain whitespace."
            Message = "Job DSL export should reject SCM credentials IDs with whitespace."
        },
        @{
            Arguments = @{
                RepoRoot = $Root
                EnvironmentPreset = $Preset
                ScmCredentialsId = "jenkins-scm'credential"
                OutputPath = (Join-Path $OutputDirectory "unsafe-scm-credentials-quote.groovy")
            }
            ExpectedMessage = "ScmCredentialsId must contain only letters, digits"
            Message = "Job DSL export should reject SCM credentials IDs with quoted metadata."
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
    Assert-TextContains -Text $seedJob -Expected "function Assert-SeedRepoUrlSafety" -Message "Seed job should validate repository URL syntax before Job DSL generation."
    Assert-TextContains -Text $seedJob -Expected "SEED_REPO_URL must not include embedded credentials; configure repository access with SEED_SCM_CREDENTIALS_ID." -Message "Seed job should reject embedded SCM credentials before Job DSL generation."
    Assert-TextContains -Text $seedJob -Expected "Assert-SeedRepoUrlSafety -Value `$env:SEED_REPO_URL" -Message "Seed job should run repository URL safety checks before exporting DSL."
    Assert-TextContains -Text $seedJob -Expected "Assert-SeedBranchSpecSafety -Value `$env:SEED_BRANCH_SPEC" -Message "Seed job should run branch-spec safety checks before exporting DSL."
    Assert-TextContains -Text $seedJob -Expected "Assert-SeedScmCredentialsIdSafety -Value `$env:SEED_SCM_CREDENTIALS_ID" -Message "Seed job should run credentials ID safety checks before exporting DSL."
    Assert-TextContains -Text $seedJob -Expected "SEED_BRANCH_SPEC must contain only letters, digits" -Message "Seed job should constrain branch-spec characters before exporting DSL."
    Assert-TextContains -Text $seedJob -Expected "SEED_SCM_CREDENTIALS_ID must contain only letters, digits" -Message "Seed job should constrain credentials ID characters before exporting DSL."
    Assert-TextContains -Text $seedJob -Expected "def hasConcreteGeneratedMetadata =" -Message "Seed job should detect concrete generated metadata before artifact archiving."
    Assert-TextContains -Text $seedJob -Expected 'params.SEED_DOCKER_REGISTRY?.trim()' -Message "Seed job should treat concrete registry overrides as generated metadata before artifact archiving."
    Assert-TextContains -Text $seedJob -Expected "Skipping generated Job DSL artifact archive because concrete SCM, registry, or credential metadata was supplied." -Message "Seed job should avoid archiving generated DSL that includes concrete SCM, registry, or credential metadata."
    Assert-TextContains -Text $seedJob -Expected 'if (-not (Test-TrueValue -Value $env:SEED_SKIP_SERVICE_JOBS))' -Message "Seed job should validate service pipeline contracts before generating service jobs."
    Assert-TextContains -Text $seedJob -Expected 'scripts\\validate-service-pipelines.ps1' -Message "Seed job should call the committed service pipeline validator before service job generation."
    Assert-TextContains -Text $seedJob -Expected '& $serviceValidationScriptPath -RepoRoot $env:WORKSPACE' -Message "Seed job should validate the current workspace service catalog."
    Assert-TextContains -Text $seedJob -Expected "function Set-ArgumentValue" -Message "Seed job should build named exporter arguments through a helper."
    Assert-TextContains -Text $seedJob -Expected "function Add-BooleanArgument" -Message "Seed job should convert Jenkins boolean parameter strings before splatting exporter arguments."
    Assert-TextContains -Text $seedJob -Expected '$arguments = @{}' -Message "Seed job should use hashtable splatting for typed exporter arguments."
    Assert-TextContains -Text $seedJob -Expected 'Add-BooleanArgument -Arguments $arguments -Name ''-UseLightweightCheckout''' -Message "Seed job should pass UseLightweightCheckout as a typed Boolean."
    Assert-TextNotMatch -Text $seedJob -Pattern '\$arguments\.Add\(''-UseLightweightCheckout''\)' -Message "Seed job should not pass UseLightweightCheckout as a raw string argument."
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
    Assert-TextContains -Text $jenkinsfile -Expected "String rawValue = value == null ? '' : value" -Message ("{0} should inspect raw artifact paths before trimming" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "must stay under out/." -Message ("{0} should require archive paths under out/" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "must be a literal path, not an Ant glob pattern." -Message ("{0} should reject archive glob patterns" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "must not contain control characters." -Message ("{0} should reject control characters in artifact paths" -f $JenkinsfilePath)
    Assert-TextContains -Text $jenkinsfile -Expected "segment == '..'" -Message ("{0} should reject parent-directory archive segments" -f $JenkinsfilePath)

    if (@($ExpectedDirectoryParameterNames).Count -gt 0) {
        Assert-TextContains -Text $jenkinsfile -Expected "String requireLiteralOutDirectoryPattern" -Message ("{0} should sanitize directory archive patterns" -f $JenkinsfilePath)
    }

    if (@($ExpectedPipelineBoundaryNames).Count -gt 0) {
        Assert-TextContains -Text $jenkinsfile -Expected '$rawValue = [string]$Value' -Message ("{0} should inspect raw script path values before trimming" -f $JenkinsfilePath)
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

function Assert-PromotionArchiveEntrySafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromotionScript,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $cases = @(
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

        $failed = $false
        $message = ""
        try {
            & $PromotionScript -RepoRoot $Root -ArchivePath $archivePath -ExtractPath $extractPath 6>$null | Out-Null
        }
        catch {
            $failed = $true
            $message = [string]$_
        }

        Assert-Condition -Condition $failed -Message ([string]$case.Message)
        Assert-TextContains -Text $message -Expected ([string]$case.ExpectedMessage) -Message ([string]$case.Message)
        Assert-Condition -Condition (-not (Test-Path -Path $escapedPath -PathType Leaf)) -Message "Promotion archive validation must not write traversal entries before failing."
    }
}
