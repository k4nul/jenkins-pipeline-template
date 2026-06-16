param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../scripts/jenkins-job-common.ps1")
. (Join-Path $PSScriptRoot "../scripts/jenkins-validation-assertions.ps1")

function Assert-CustomDirectSelectionPlan {
    param(
        [object]$Plan
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Custom direct selection should produce one selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "Custom direct selection should skip service jobs when requested"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "feature-blue-green" -Message "Custom selection name should be path-safe"
    Assert-Condition -Condition (-not [bool]$selection.UsesPreset) -Message "Custom direct selection should not be marked as preset-backed"
    Assert-Equal `
        -Actual ([string]$selection.BundleFolderPath) `
        -Expected "team/bundles/feature-blue-green" `
        -Message "Custom selection should use the requested bundle root"
    Assert-Equal `
        -Actual ([string]$selection.ValidationJobPath) `
        -Expected "team/bundles/feature-blue-green/repository-validation" `
        -Message "Custom validation job path"
    Assert-Equal `
        -Actual ([string]$selection.DeliveryJobPath) `
        -Expected "team/bundles/feature-blue-green/bundle-delivery" `
        -Message "Custom delivery job path"
    Assert-Equal `
        -Actual ([string]$selection.PromotionJobPath) `
        -Expected "team/bundles/feature-blue-green/bundle-promotion" `
        -Message "Custom promotion job path"
    Assert-Equal `
        -Actual ([string]$selection.ValuesFile) `
        -Expected "config/custom-values.env" `
        -Message "Custom values file should be preserved"
    Assert-Equal `
        -Actual ([string]$selection.DockerRegistry) `
        -Expected "registry.example.invalid/team" `
        -Message "Custom Docker registry should be preserved"
    Assert-Equal -Actual ([string]$selection.Version) -Expected "1.2.3" -Message "Custom version should be preserved"
    Assert-Equal `
        -Actual ([string]$selection.BundleOutputPath) `
        -Expected "out/delivery/custom" `
        -Message "Custom bundle output path should be preserved"
    Assert-Equal `
        -Actual ([string]$selection.ArchivePath) `
        -Expected "out/delivery/custom.zip" `
        -Message "Custom archive path should be preserved"
    Assert-Equal `
        -Actual ([string]$selection.PromotionExtractPath) `
        -Expected "out/promotion/custom" `
        -Message "Custom promotion extract path should be preserved"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-ContainsItem `
        -Values @($validationJob.KeyParameters) `
        -Expected "VALIDATION_PROFILE=web-platform" `
        -Message "Custom validation job should expose the profile parameter"
    Assert-ContainsItem `
        -Values @($validationJob.KeyParameters) `
        -Expected "VALIDATION_APPLICATIONS=nginx-web, whoami" `
        -Message "Custom validation job should expose application parameters"
    Assert-ContainsItem `
        -Values @($validationJob.KeyParameters) `
        -Expected "VALIDATION_DATA_SERVICES=redis" `
        -Message "Custom validation job should expose data service parameters"
    Assert-ContainsItem `
        -Values @($validationJob.KeyParameters) `
        -Expected "VALIDATION_DOCKER_REGISTRY=registry.example.invalid/team" `
        -Message "Custom validation job should expose the Docker registry parameter"
    Assert-ContainsItem `
        -Values @($deliveryJob.KeyParameters) `
        -Expected "BUNDLE_OUTPUT_PATH=out/delivery/custom" `
        -Message "Custom delivery job should expose the bundle output path"
    Assert-ContainsItem `
        -Values @($deliveryJob.KeyParameters) `
        -Expected "BUNDLE_ARCHIVE_PATH=out/delivery/custom.zip" `
        -Message "Custom delivery job should expose the archive path"
    Assert-ContainsItem `
        -Values @($deliveryJob.KeyParameters) `
        -Expected "BUNDLE_DOCKER_REGISTRY=registry.example.invalid/team" `
        -Message "Custom delivery job should expose the Docker registry parameter"
    Assert-ContainsItem `
        -Values @($promotionJob.KeyParameters) `
        -Expected "PROMOTION_ARCHIVE_PATH=out/delivery/custom.zip" `
        -Message "Custom promotion job should expose the archive path"
    Assert-ContainsItem `
        -Values @($promotionJob.KeyParameters) `
        -Expected "PROMOTION_EXTRACT_PATH=out/promotion/custom" `
        -Message "Custom promotion job should expose the extract path"

    Assert-Condition `
        -Condition (-not (@($validationJob.KeyParameters) -contains "VALIDATION_ENVIRONMENT_PRESET=feature-blue-green")) `
        -Message "Custom validation job should not invent a preset parameter"
    Assert-ContainsItem `
        -Values @($deliveryJob.UpstreamDependencies) `
        -Expected ([string]$validationJob.Path) `
        -Message "Custom delivery should depend on validation"
    Assert-ContainsItem `
        -Values @($promotionJob.UpstreamDependencies) `
        -Expected ([string]$deliveryJob.Path) `
        -Message "Custom promotion should depend on delivery"
}

function Assert-CustomDirectSelectionDsl {
    param(
        [string]$DslPath,
        [object]$Plan
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated custom direct-selection DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "// Service job count: 0" -Message "Custom direct-selection DSL should record that service jobs were skipped"
    Assert-TextContains -Text $dsl -Expected "boolean useLightweightCheckout = false" -Message "Custom direct-selection DSL should honor the lightweight checkout override"
    Assert-TextContains -Text $dsl -Expected "folder('team')" -Message "Custom direct-selection DSL should create the top-level custom folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/bundles')" -Message "Custom direct-selection DSL should create the requested bundle root folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/bundles/feature-blue-green')" -Message "Custom direct-selection DSL should create the sanitized selection folder"
    Assert-TextContains -Text $dsl -Expected "folder('team/services')" -Message "Custom direct-selection DSL should create the requested service root folder"
    Assert-TextNotMatch -Text $dsl -Pattern "pipelineJob\('team/services/" -Message "Custom direct-selection DSL should not generate service jobs when service jobs are skipped"
    Assert-TextContains -Text $dsl -Expected "VALIDATION_DOCKER_REGISTRY=registry.example.invalid/team" -Message "Custom direct-selection DSL should preserve the validation Docker registry parameter"
    Assert-TextContains -Text $dsl -Expected "BUNDLE_DOCKER_REGISTRY=registry.example.invalid/team" -Message "Custom direct-selection DSL should preserve the delivery Docker registry parameter"

    foreach ($selection in @($Plan.Selections)) {
        foreach ($job in @($selection.PipelineJobs)) {
            Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Custom direct-selection DSL should include job {0}" -f $job.Path)
            Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Custom direct-selection DSL should include Jenkinsfile {0}" -f $job.Jenkinsfile)
        }
    }
}

function Assert-SelectionNameOnlyPlanAndDsl {
    param(
        [object]$Plan,
        [string]$DslPath
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "SelectionName-only plan should produce one custom selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "SelectionName-only plan should not create public service jobs by default"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "release-candidate" -Message "SelectionName-only plan should sanitize the custom selection name"
    Assert-Condition -Condition (-not [bool]$selection.UsesPreset) -Message "SelectionName-only plan should not be marked as preset-backed"
    Assert-Equal -Actual ([string]$selection.Profile) -Expected "web-platform" -Message "SelectionName-only plan should use the default profile"
    Assert-Equal -Actual ([string]$selection.ValuesFile) -Expected "config\platform-values.env.example" -Message "SelectionName-only plan should use the public-safe default values file"
    Assert-Equal -Actual ([string]$selection.Version) -Expected "0.0.0-ci" -Message "SelectionName-only plan should use the CI default version"
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected "platform/release-candidate" -Message "SelectionName-only bundle folder path"
    Assert-Equal -Actual ([string]$selection.ValidationJobPath) -Expected "platform/release-candidate/repository-validation" -Message "SelectionName-only validation job path"
    Assert-Equal -Actual ([string]$selection.DeliveryJobPath) -Expected "platform/release-candidate/bundle-delivery" -Message "SelectionName-only delivery job path"
    Assert-Equal -Actual ([string]$selection.PromotionJobPath) -Expected "platform/release-candidate/bundle-promotion" -Message "SelectionName-only promotion job path"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    Assert-Condition `
        -Condition (-not (@($validationJob.KeyParameters) -contains "VALIDATION_ENVIRONMENT_PRESET=release-candidate")) `
        -Message "SelectionName-only validation job should not invent an environment preset parameter"

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated SelectionName-only DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "// Selection count: 1" -Message "SelectionName-only DSL should record one custom selection"
    Assert-TextContains -Text $dsl -Expected "folder('platform/release-candidate')" -Message "SelectionName-only DSL should create the custom selection folder"
    Assert-TextContains -Text $dsl -Expected "pipelineJob('platform/release-candidate/repository-validation')" -Message "SelectionName-only DSL should include the custom validation job"
    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message "SelectionName-only DSL should keep the SCM URL parameterized"
    Assert-TextNotMatch -Text $dsl -Pattern "VALIDATION_ENVIRONMENT_PRESET=" -Message "SelectionName-only DSL should not emit preset-backed validation parameters"
    Assert-TextNotMatch -Text $dsl -Pattern "BUNDLE_ENVIRONMENT_PRESET=" -Message "SelectionName-only DSL should not emit preset-backed delivery parameters"
    Assert-TextNotMatch -Text $dsl -Pattern "PROMOTION_ENVIRONMENT_PRESET=" -Message "SelectionName-only DSL should not emit preset-backed promotion parameters"
    Assert-TextNotMatch -Text $dsl -Pattern "pipelineJob\('platform/(dev|staging|prod)/" -Message "SelectionName-only DSL should not fall back to the full preset matrix"
}

function Invoke-ScriptExpectingFailure {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments,
        [string]$ExpectedMessage,
        [string]$Message
    )

    $failed = $false
    $failureMessage = ""

    try {
        & $ScriptPath @Arguments 6>$null | Out-Null
    }
    catch {
        $failed = $true
        $failureMessage = [string]$_
    }

    Assert-Condition -Condition $failed -Message $Message
    Assert-TextContains -Text $failureMessage -Expected $ExpectedMessage -Message ("Failure should explain rejected Job DSL path input: {0}" -f $ExpectedMessage)
}

function Assert-NestedRootPlanAndDsl {
    param(
        [object]$Plan,
        [string]$DslPath
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "Nested-root selection should produce one selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "Nested-root selection should skip service jobs"

    $selection = $Plan.Selections | Select-Object -First 1
    Assert-Equal -Actual ([string]$selection.Name) -Expected "qa-blue-canary" -Message "Nested-root selection name should be path-safe"
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected "team/platform/bundles/qa-blue-canary" -Message "Nested bundle folder path"
    Assert-Equal -Actual ([string]$selection.ValidationJobPath) -Expected "team/platform/bundles/qa-blue-canary/repository-validation" -Message "Nested validation job path"
    Assert-Equal -Actual ([string]$selection.DeliveryJobPath) -Expected "team/platform/bundles/qa-blue-canary/bundle-delivery" -Message "Nested delivery job path"
    Assert-Equal -Actual ([string]$selection.PromotionJobPath) -Expected "team/platform/bundles/qa-blue-canary/bundle-promotion" -Message "Nested promotion job path"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message "Nested-root delivery should depend on validation"
    Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message "Nested-root promotion should depend on delivery"

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated nested-root DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    foreach ($folderPath in @(
        "team",
        "team/platform",
        "team/platform/bundles",
        "team/platform/bundles/qa-blue-canary",
        "team/services",
        "team/services/shared"
    )) {
        Assert-TextContains -Text $dsl -Expected ("folder('{0}')" -f $folderPath) -Message ("Nested-root DSL should include folder {0}" -f $folderPath)
    }

    foreach ($job in @($selection.PipelineJobs)) {
        Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $job.Path) -Message ("Nested-root DSL should include job {0}" -f $job.Path)
        Assert-TextContains -Text $dsl -Expected ([string]$job.Jenkinsfile).Replace("\", "/") -Message ("Nested-root DSL should include Jenkinsfile {0}" -f $job.Jenkinsfile)
    }
}

function Assert-ServiceJobFixtureDsl {
    param(
        [object]$Plan,
        [string]$DslPath
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated service-job fixture DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    $serviceJobs = @($Plan.ServiceJobs | Where-Object { [string]$_.Name -eq "nginx-web" })
    Assert-Equal -Actual $serviceJobs.Count -Expected 1 -Message "Service-job fixture DSL assertions require one nginx-web service job"
    $serviceJob = $serviceJobs[0]

    Assert-TextContains -Text $dsl -Expected "// Service job count: 1" -Message "Service-job fixture DSL should record the generated service job count"
    Assert-TextContains -Text $dsl -Expected "folder('services')" -Message "Service-job fixture DSL should create the service job root folder"
    Assert-TextContains -Text $dsl -Expected ("pipelineJob('{0}')" -f $serviceJob.Path) -Message "Service-job fixture DSL should include the Jenkinsfile-backed service job"
    Assert-TextContains -Text $dsl -Expected "configureGeneratedPipelineJob(delegate, 'services/nginx-web/Jenkinsfile'" -Message "Service-job fixture DSL should point service jobs at service-local Jenkinsfiles"
    Assert-TextContains -Text $dsl -Expected "Generated service image pipeline job." -Message "Service-job fixture DSL should describe service image jobs distinctly from bundle jobs"
    Assert-TextContains -Text $dsl -Expected "Service: nginx-web" -Message "Service-job fixture DSL should include service identity in the description"
    Assert-TextContains -Text $dsl -Expected "Category: fixture-service" -Message "Service-job fixture DSL should include service category metadata"
    Assert-TextContains -Text $dsl -Expected "Image name: fixture/nginx-web:1.0.0" -Message "Service-job fixture DSL should include the public image name"
    Assert-TextContains -Text $dsl -Expected "Used by selections: service-job-fixture" -Message "Service-job fixture DSL should preserve the selection-to-service relationship"
    Assert-TextContains -Text $dsl -Expected "Required environment variables: DOCKER_REGISTRY" -Message "Service-job fixture DSL should document required service environment variables"
    Assert-TextContains -Text $dsl -Expected "Optional environment variables: CACHE" -Message "Service-job fixture DSL should document optional service environment variables"
    Assert-TextContains -Text $dsl -Expected "Upstream artifact inputs:" -Message "Service-job fixture DSL should include upstream artifact input guidance"
    Assert-TextContains -Text $dsl -Expected "Consumes the bundle validation output before publishing a service image." -Message "Service-job fixture DSL should include service artifact input notes"
    Assert-TextNotMatch -Text $dsl -Pattern "pipelineJob\('services/nginx-web/.+'\)" -Message "Service-job fixture DSL should keep one service job at the service root, not nested under generated children"
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

function Assert-DependencyInventory {
    param(
        [object]$Inventory
    )

    Assert-Equal -Actual ([string]$Inventory.Status) -Expected "passed" -Message "Dependency inventory should pass"
    Assert-Equal -Actual ([int]@($Inventory.PackageManagerManifests).Count) -Expected 0 -Message "Template should not currently report package-manager manifests"
    Assert-Equal -Actual ([int]@($Inventory.ServiceImages).Count) -Expected 4 -Message "Dependency inventory should include the public service images"
    Assert-Equal -Actual ([int]@($Inventory.ControllerImages).Count) -Expected 1 -Message "Dependency inventory should include the Jenkins controller example image"

    $controllerImage = @($Inventory.ControllerImages | Select-Object -First 1)[0]
    Assert-Equal -Actual ([string]$controllerImage.ImageReference) -Expected "jenkins/jenkins:lts" -Message "Dependency inventory should report the public controller example image"
    Assert-Condition -Condition ([bool]$controllerImage.UsesFloatingTag) -Message "Dependency inventory should flag the floating Jenkins LTS example tag"
    Assert-TextContains `
        -Text (@($Inventory.RiskIndicators) -join [Environment]::NewLine) `
        -Expected "No package-manager manifests or lockfiles were found" `
        -Message "Dependency inventory should explain manifest-free dependency posture"
}

$context = Initialize-JenkinsValidationContext `
    -RepoRoot $RepoRoot `
    -DefaultRoot (Join-Path $PSScriptRoot "..") `
    -OutputDirectory "out/jenkins/tests/public-presets"

$root = $context.Root
$jobPlanScript = $context.Paths.JobPlanScript
$jobDslScript = $context.Paths.JobDslScript
$dependencyInventoryScript = $context.Paths.DependencyInventoryScript
$seedJobPath = $context.Paths.SeedJobPath
$deliveryJobPath = $context.Paths.DeliveryJobPath
$promotionJobPath = $context.Paths.PromotionJobPath
$outputDirectory = $context.OutputDirectory
$presets = @($context.Presets)
$servicePlan = $context.ServicePlan
$serviceIndex = $context.ServiceIndex

foreach ($preset in $presets) {
    $plan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = @($preset)
        Format = "json"
    }

    Assert-JenkinsPresetJobPlan -Plan $plan -Preset $preset -ServiceIndex $serviceIndex

    $dslPath = Join-Path $outputDirectory ("{0}-seed-job-dsl.groovy" -f $preset)
    & $jobDslScript -RepoRoot $root -EnvironmentPreset $preset -OutputPath $dslPath 6>$null | Out-Null
    Assert-GeneratedDsl -DslPath $dslPath -Plan $plan -Preset $preset
}

$explicitScmPreset = [string]($presets | Select-Object -First 1)
$explicitScmDslPath = Join-Path $outputDirectory ("{0}-explicit-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "git@example.invalid:org/repo.git" `
    -BranchSpec "*/feature/quote'safe" `
    -ScmCredentialsId "jenkins-scm'credentials" `
    -OutputPath $explicitScmDslPath 6>$null | Out-Null
Assert-ExplicitScmDsl -DslPath $explicitScmDslPath
Assert-JobDslScmInputValidation `
    -ScriptPath $jobDslScript `
    -Root $root `
    -OutputDirectory $outputDirectory `
    -Preset $explicitScmPreset

$multiPresetNames = @("dev", "staging")
$multiPresetPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    EnvironmentPreset = $multiPresetNames
    Format = "json"
}
$multiPresetDslPath = Join-Path $outputDirectory "multi-preset-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $multiPresetNames `
    -OutputPath $multiPresetDslPath 6>$null | Out-Null
Assert-MultiPresetPlanAndDsl -Plan $multiPresetPlan -ExpectedPresets $multiPresetNames -DslPath $multiPresetDslPath

$customDirectSelectionPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "feature/blue green"
    Profile = "web-platform"
    Applications = @("nginx-web", "whoami")
    DataServices = @("redis")
    ValuesFile = "config/custom-values.env"
    DockerRegistry = "registry.example.invalid/team"
    Version = "1.2.3"
    BundleOutputPath = "out/delivery/custom"
    ArchivePath = "out/delivery/custom.zip"
    PromotionExtractPath = "out/promotion/custom"
    JobRoot = "team/bundles"
    ServiceJobRoot = "team/services"
    SkipServiceJobs = $true
    Format = "json"
}
Assert-CustomDirectSelectionPlan -Plan $customDirectSelectionPlan

$customDirectSelectionDslPath = Join-Path $outputDirectory "custom-direct-selection-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "feature/blue green" `
    -Profile "web-platform" `
    -Applications @("nginx-web", "whoami") `
    -DataServices @("redis") `
    -ValuesFile "config/custom-values.env" `
    -DockerRegistry "registry.example.invalid/team" `
    -Version "1.2.3" `
    -BundleOutputPath "out/delivery/custom" `
    -ArchivePath "out/delivery/custom.zip" `
    -PromotionExtractPath "out/promotion/custom" `
    -JobRoot "team/bundles" `
    -ServiceJobRoot "team/services" `
    -SkipServiceJobs `
    -UseLightweightCheckout:$false `
    -OutputPath $customDirectSelectionDslPath 6>$null | Out-Null
Assert-CustomDirectSelectionDsl -DslPath $customDirectSelectionDslPath -Plan $customDirectSelectionPlan

$selectionNameOnlyPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "release/candidate"
    Format = "json"
}
$selectionNameOnlyDslPath = Join-Path $outputDirectory "selection-name-only-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "release/candidate" `
    -OutputPath $selectionNameOnlyDslPath 6>$null | Out-Null
Assert-SelectionNameOnlyPlanAndDsl -Plan $selectionNameOnlyPlan -DslPath $selectionNameOnlyDslPath

$nestedRootPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "qa/blue canary"
    Profile = "web-platform"
    Applications = @("nginx-web", "whoami")
    DataServices = @("redis")
    JobRoot = "team/platform/bundles"
    ServiceJobRoot = "team/services/shared"
    SkipServiceJobs = $true
    Format = "json"
}
$nestedRootDslPath = Join-Path $outputDirectory "nested-root-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "qa/blue canary" `
    -Profile "web-platform" `
    -Applications @("nginx-web", "whoami") `
    -DataServices @("redis") `
    -JobRoot "team/platform/bundles" `
    -ServiceJobRoot "team/services/shared" `
    -SkipServiceJobs `
    -OutputPath $nestedRootDslPath 6>$null | Out-Null
Assert-NestedRootPlanAndDsl -Plan $nestedRootPlan -DslPath $nestedRootDslPath

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobPlanScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "unsafe-root"
        Profile = "web-platform"
        JobRoot = "../team"
        Format = "json"
    } `
    -ExpectedMessage "Jenkins job path segment is not allowed" `
    -Message "Job plan generation should reject parent-directory JobRoot segments"

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobDslScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "unsafe-service-root"
        Profile = "web-platform"
        ServiceJobRoot = 'services/${name}'
        OutputPath = "out/jenkins/tests/public-presets/unsafe-service-root-seed-job-dsl.groovy"
    } `
    -ExpectedMessage "Jenkins job path segment is not allowed" `
    -Message "Job DSL export should reject unsafe ServiceJobRoot segments"

$serviceJobFixtureRoot = New-JenkinsServiceJobFixtureRoot -Root $root -OutputDirectory $outputDirectory
$serviceJobFixturePlanScript = Join-Path $serviceJobFixtureRoot "scripts/show-jenkins-job-plan.ps1"
$serviceJobFixtureDslScript = Join-Path $serviceJobFixtureRoot "scripts/export-jenkins-job-dsl.ps1"
$serviceJobFixtureValidationScript = Join-Path $serviceJobFixtureRoot "scripts/validate-service-pipelines.ps1"
$serviceJobFixtureDslOutputPath = "out/jenkins/tests/service-job-fixture-seed-job-dsl.groovy"
$serviceJobFixtureDslPath = Join-Path $serviceJobFixtureRoot $serviceJobFixtureDslOutputPath
$sharedServiceJobRoot = "team/services/images"
$sharedServiceJobFixtureDslOutputPath = "out/jenkins/tests/shared-service-job-fixture-seed-job-dsl.groovy"
$sharedServiceJobFixtureDslPath = Join-Path $serviceJobFixtureRoot $sharedServiceJobFixtureDslOutputPath

$serviceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixturePlanScript -Arguments @{
    RepoRoot = $serviceJobFixtureRoot
    SelectionName = "service-job-fixture"
    Profile = "web-platform"
    Applications = @("nginx-web")
    Format = "json"
}
Assert-JenkinsServiceJobFixturePlan -Plan $serviceJobFixturePlan

& $serviceJobFixtureDslScript `
    -RepoRoot $serviceJobFixtureRoot `
    -SelectionName "service-job-fixture" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -OutputPath $serviceJobFixtureDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixtureDslPath -Plan $serviceJobFixturePlan -Preset "service-job-fixture"
Assert-ServiceJobFixtureDsl -Plan $serviceJobFixturePlan -DslPath $serviceJobFixtureDslPath

$sharedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixturePlanScript -Arguments @{
    RepoRoot = $serviceJobFixtureRoot
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    ServiceJobRoot = $sharedServiceJobRoot
    Format = "json"
}
Assert-JenkinsServiceJobSharedPresetPlan -Plan $sharedServiceJobFixturePlan -ExpectedServiceJobRoot $sharedServiceJobRoot

& $serviceJobFixtureDslScript `
    -RepoRoot $serviceJobFixtureRoot `
    -EnvironmentPreset @("fixture-alpha", "fixture-beta") `
    -ServiceJobRoot $sharedServiceJobRoot `
    -OutputPath $sharedServiceJobFixtureDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $sharedServiceJobFixtureDslPath -Plan $sharedServiceJobFixturePlan -Preset "shared-service-job-fixture"
Assert-ServiceJobSharedPresetDsl -Plan $sharedServiceJobFixturePlan -DslPath $sharedServiceJobFixtureDslPath -ExpectedServiceJobRoot $sharedServiceJobRoot

$skippedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixturePlanScript -Arguments @{
    RepoRoot = $serviceJobFixtureRoot
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    SkipServiceJobs = $true
    Format = "json"
}
Assert-JenkinsServiceJobsSkippedPlan -Plan $skippedServiceJobFixturePlan

& $serviceJobFixtureValidationScript -RepoRoot $serviceJobFixtureRoot 6>$null | Out-Null
Assert-MissingServiceJenkinsfileValidationFails -Root $root -OutputDirectory $outputDirectory
Assert-UnsafeServiceCatalogNamesFail -Root $root -OutputDirectory $outputDirectory

$dependencyInventory = Invoke-JsonScript -ScriptPath $dependencyInventoryScript -Arguments @{
    RepoRoot = $root
    Format = "json"
}
Assert-DependencyInventory -Inventory $dependencyInventory

Assert-SeedJobSafety -SeedJobPath $seedJobPath
Assert-JenkinsfileArtifactPathSafety -JenkinsfilePath $seedJobPath -ExpectedParameterNames @("SEED_OUTPUT_PATH")
Assert-JenkinsfileArtifactPathSafety `
    -JenkinsfilePath $deliveryJobPath `
    -ExpectedParameterNames @("BUNDLE_ARCHIVE_PATH") `
    -ExpectedDirectoryParameterNames @("BUNDLE_OUTPUT_PATH") `
    -ExpectedPipelineBoundaryNames @("BUNDLE_OUTPUT_PATH", "BUNDLE_ARCHIVE_PATH")
Assert-JenkinsfileArtifactPathSafety `
    -JenkinsfilePath $promotionJobPath `
    -ExpectedParameterNames @("PROMOTION_ARCHIVE_PATH") `
    -ExpectedDirectoryParameterNames @("PROMOTION_EXTRACT_PATH") `
    -ExpectedPipelineBoundaryNames @("PROMOTION_ARCHIVE_PATH", "PROMOTION_EXTRACT_PATH")
Assert-JenkinsfileDeploymentApprovalSafety `
    -JenkinsfilePath $deliveryJobPath `
    -DeployParameterName "BUNDLE_DEPLOY" `
    -DryRunParameterName "BUNDLE_DEPLOY_DRY_RUN" `
    -RequireSecretsParameterName "BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY" `
    -RequireStatusParameterName "BUNDLE_REQUIRE_BOOTSTRAP_STATUS"
Assert-JenkinsfileDeploymentApprovalSafety `
    -JenkinsfilePath $promotionJobPath `
    -DeployParameterName "PROMOTION_DEPLOY" `
    -DryRunParameterName "PROMOTION_DEPLOY_DRY_RUN" `
    -RequireSecretsParameterName "PROMOTION_REQUIRE_BOOTSTRAP_SECRETS_READY" `
    -RequireStatusParameterName "PROMOTION_REQUIRE_BOOTSTRAP_STATUS"

Write-Output ("Jenkins public preset tests passed for presets: {0}" -f ($presets -join ", "))
Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
Write-Output "Validated unsafe SCM inputs fail closed before Job DSL generation."
Write-Output ("Validated multi-preset Job DSL fixture: {0}" -f $multiPresetDslPath)
Write-Output ("Validated custom direct-selection Job DSL fixture: {0}" -f $customDirectSelectionDslPath)
Write-Output ("Validated SelectionName-only Job DSL fixture: {0}" -f $selectionNameOnlyDslPath)
Write-Output ("Validated nested Job DSL root fixture: {0}" -f $nestedRootDslPath)
Write-Output "Validated unsafe Job DSL root segments fail closed."
Write-Output ("Validated Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixtureDslPath)
Write-Output ("Validated shared Jenkinsfile-backed service job fixture: {0}" -f $sharedServiceJobFixtureDslPath)
Write-Output "Validated SkipServiceJobs suppresses Jenkinsfile-backed service jobs."
Write-Output "Validated missing Jenkinsfile-backed service jobs fail closed."
Write-Output "Validated dependency inventory risk indicators."
Write-Output "Validated seed job SCM apply and destructive delete confirmation guards."
Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
Write-Output "Validated non-dry-run delivery and promotion deployment approval guards."
Write-Output "Validated committed Jenkins runtime entrypoints and public-safe values defaults."
