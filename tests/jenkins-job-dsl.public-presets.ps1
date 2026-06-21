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

    $selection = @($Plan.Selections)[0]
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

    $selection = @($Plan.Selections)[0]
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

function Assert-EscapedMetadataDsl {
    param(
        [string]$DslPath
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated escaped-metadata DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "folder('platform/quote-safe')" -Message "Escaped metadata DSL should sanitize the custom selection name"
    Assert-TextContains -Text $dsl -Expected "description('Generated bundle job folder for selection \'quote-safe\' using profile \'web-platform\'.')" -Message "Escaped metadata DSL should escape quoted folder descriptions"
    Assert-TextContains -Text $dsl -Expected "Generated bundle pipeline job.\nSelection: quote-safe\nProfile: web-platform" -Message "Escaped metadata DSL should encode description newlines as Groovy string escapes"
    Assert-TextContains -Text $dsl -Expected 'VALIDATION_VALUES_FILE=config\\quoted\''value.env' -Message "Escaped metadata DSL should preserve and escape quoted validation values paths"
    Assert-TextContains -Text $dsl -Expected 'VALIDATION_DOCKER_REGISTRY=registry.example.invalid/team\\release\''s' -Message "Escaped metadata DSL should preserve and escape quoted registry values"
    Assert-TextContains -Text $dsl -Expected 'BUNDLE_OUTPUT_PATH=out\\delivery\\quoted value' -Message "Escaped metadata DSL should preserve delivery output paths with spaces"
    Assert-TextContains -Text $dsl -Expected 'BUNDLE_ARCHIVE_PATH=out\\delivery\\quoted bundle\''s.zip' -Message "Escaped metadata DSL should preserve and escape quoted bundle archive paths"
    Assert-TextContains -Text $dsl -Expected 'PROMOTION_ARCHIVE_PATH=out\\delivery\\quoted bundle\''s.zip' -Message "Escaped metadata DSL should preserve and escape quoted promotion archive paths"
    Assert-TextContains -Text $dsl -Expected 'PROMOTION_EXTRACT_PATH=out\\promotion\\quoted folder' -Message "Escaped metadata DSL should preserve promotion extract paths with spaces"
    Assert-TextContains -Text $dsl -Expected '-ValuesFile \''config\\quoted\''\''value.env\''' -Message "Escaped metadata DSL should double quotes inside embedded PowerShell values file arguments"
    Assert-TextContains -Text $dsl -Expected '-DockerRegistry \''registry.example.invalid/team\\release\''\''s\''' -Message "Escaped metadata DSL should double quotes inside embedded PowerShell registry arguments"
    Assert-TextContains -Text $dsl -Expected '-Version \''2.0.0-beta\''\''1\''' -Message "Escaped metadata DSL should double quotes inside embedded PowerShell version arguments"
    Assert-TextContains -Text $dsl -Expected '-ArchivePath \''out\\delivery\\quoted bundle\''\''s.zip\''' -Message "Escaped metadata DSL should double quotes inside embedded PowerShell archive arguments"

    Assert-Condition -Condition (-not $dsl.Contains("VALIDATION_VALUES_FILE=config\quoted'value.env")) -Message "Escaped metadata DSL should not emit raw quoted validation values paths"
    Assert-Condition -Condition (-not $dsl.Contains("BUNDLE_ARCHIVE_PATH=out\delivery\quoted bundle's.zip")) -Message "Escaped metadata DSL should not emit raw quoted archive paths"
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

    $selection = @($Plan.Selections)[0]
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

function Assert-IncludeJenkinsBoundaryPlanAndDsl {
    param(
        [object]$Plan,
        [string]$DslPath
    )

    Assert-Equal -Actual ([int]$Plan.SelectionCount) -Expected 1 -Message "IncludeJenkins boundary selection should produce one selection"
    Assert-Equal -Actual ([int]$Plan.ServiceJobCount) -Expected 0 -Message "IncludeJenkins boundary selection should skip service jobs when requested"

    $selection = @($Plan.Selections)[0]
    Assert-Equal -Actual ([string]$selection.Name) -Expected "jenkins-controller-boundary" -Message "IncludeJenkins boundary selection name should be path-safe"
    Assert-Condition -Condition ([bool]$selection.IncludeJenkins) -Message "IncludeJenkins boundary selection should opt into Jenkins controller manifests"
    Assert-Condition -Condition (-not [bool]$selection.UsesPreset) -Message "IncludeJenkins boundary selection should remain an explicit custom selection"
    Assert-Equal -Actual ([string]$selection.BundleFolderPath) -Expected "platform/jenkins-controller-boundary" -Message "IncludeJenkins boundary bundle folder path"

    $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
    $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
    $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

    Assert-ContainsItem -Values @($validationJob.KeyParameters) -Expected "VALIDATION_INCLUDE_JENKINS=true" -Message "IncludeJenkins validation job should expose the Jenkins-controller opt-in"
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected "BUNDLE_INCLUDE_JENKINS=true" -Message "IncludeJenkins delivery job should expose the Jenkins-controller opt-in"
    Assert-ContainsItem -Values @($deliveryJob.KeyParameters) -Expected "BUNDLE_DEPLOY=false" -Message "IncludeJenkins delivery job should keep deploy disabled by default"
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_DEPLOY=false" -Message "IncludeJenkins promotion job should keep deploy disabled by default"
    Assert-ContainsItem -Values @($promotionJob.KeyParameters) -Expected "PROMOTION_DEPLOY_DRY_RUN=true" -Message "IncludeJenkins promotion job should keep dry-run enabled by default"

    Assert-TextContains -Text ([string]$validationJob.LocalCommand) -Expected "-IncludeJenkins" -Message "IncludeJenkins validation command should pass the Jenkins-controller opt-in"
    Assert-TextContains -Text ([string]$deliveryJob.LocalCommand) -Expected "-IncludeJenkins" -Message "IncludeJenkins delivery command should pass the Jenkins-controller opt-in"
    Assert-Condition -Condition (-not ([string]$promotionJob.LocalCommand).Contains("-IncludeJenkins")) -Message "IncludeJenkins promotion command should not change promotion scope"

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated IncludeJenkins boundary DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected "folder('platform/jenkins-controller-boundary')" -Message "IncludeJenkins DSL should create the explicit controller-boundary selection folder"
    Assert-TextContains -Text $dsl -Expected "VALIDATION_INCLUDE_JENKINS=true" -Message "IncludeJenkins DSL should document the validation opt-in parameter"
    Assert-TextContains -Text $dsl -Expected "BUNDLE_INCLUDE_JENKINS=true" -Message "IncludeJenkins DSL should document the delivery opt-in parameter"
    Assert-TextContains -Text $dsl -Expected "BUNDLE_DEPLOY=false" -Message "IncludeJenkins DSL should keep delivery deployment disabled by default"
    Assert-TextContains -Text $dsl -Expected "PROMOTION_DEPLOY=false" -Message "IncludeJenkins DSL should keep promotion deployment disabled by default"
    Assert-TextContains -Text $dsl -Expected "PROMOTION_DEPLOY_DRY_RUN=true" -Message "IncludeJenkins DSL should keep promotion dry-run enabled by default"
    Assert-TextContains -Text $dsl -Expected "-IncludeJenkins" -Message "IncludeJenkins DSL should include local validation and delivery commands with the opt-in switch"
    Assert-TextContains -Text $dsl -Expected "String repoUrl = 'REPLACE_WITH_REPOSITORY_URL'" -Message "IncludeJenkins DSL should keep the SCM URL parameterized"
    Assert-TextContains -Text $dsl -Expected "String branchSpec = 'REPLACE_WITH_BRANCH_SPEC'" -Message "IncludeJenkins DSL should keep the branch spec parameterized"
    Assert-TextContains -Text $dsl -Expected "String scmCredentialsId = ''" -Message "IncludeJenkins DSL should keep credentials unset by default"
    Assert-TextNotMatch -Text $dsl -Pattern "https?://|git@" -Message "IncludeJenkins DSL should not include concrete SCM URLs"
}

function Assert-ScmVariantDsl {
    param(
        [string]$DslPath,
        [string]$ExpectedRepoUrl,
        [string]$ExpectedBranchSpec,
        [string]$ExpectedScmCredentialsId = ""
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated SCM variant DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    Assert-TextContains -Text $dsl -Expected ("String repoUrl = '{0}'" -f $ExpectedRepoUrl.Replace("\", "\\").Replace("'", "\'")) -Message "SCM variant DSL should preserve and escape the repository URL"
    Assert-TextContains -Text $dsl -Expected ("String branchSpec = '{0}'" -f $ExpectedBranchSpec.Replace("\", "\\").Replace("'", "\'")) -Message "SCM variant DSL should preserve and escape the branch spec"
    Assert-TextContains -Text $dsl -Expected ("String scmCredentialsId = '{0}'" -f $ExpectedScmCredentialsId.Replace("\", "\\").Replace("'", "\'")) -Message "SCM variant DSL should preserve and escape the credentials ID"
    Assert-TextContains -Text $dsl -Expected "url(repoUrl)" -Message "SCM variant DSL should keep the repository URL parameterized"
    Assert-TextContains -Text $dsl -Expected "branch(branchSpec)" -Message "SCM variant DSL should keep branch selection parameterized"
    Assert-TextContains -Text $dsl -Expected "credentials(scmCredentialsId)" -Message "SCM variant DSL should keep credentials parameterized"
    Assert-TextNotMatch -Text $dsl -Pattern "url\(['""]" -Message "SCM variant DSL should not inline repository URL calls"
    Assert-TextNotMatch -Text $dsl -Pattern "branch\(['""]" -Message "SCM variant DSL should not inline branch calls"
    Assert-TextNotMatch -Text $dsl -Pattern "credentials\(['""]" -Message "SCM variant DSL should not inline credentials calls"
    Assert-TextNotMatch -Text $dsl -Pattern "user:token|password=" -Message "SCM variant DSL should not contain embedded credential material"
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

function Assert-DependencyInventory {
    param(
        [object]$Inventory
    )

    Assert-Equal -Actual ([string]$Inventory.Status) -Expected "passed" -Message "Dependency inventory should pass"
    Assert-Equal -Actual ([int]@($Inventory.PackageManagerManifests).Count) -Expected 0 -Message "Template should not currently report package-manager manifests"
    Assert-Equal -Actual ([int]@($Inventory.ServiceImages).Count) -Expected 4 -Message "Dependency inventory should include the public service images"
    Assert-Equal -Actual ([int]@($Inventory.ControllerImages).Count) -Expected 1 -Message "Dependency inventory should include the Jenkins controller example image"
    Assert-Equal -Actual ([int]@($Inventory.JenkinsAgentToolContracts).Count) -Expected 4 -Message "Dependency inventory should include Jenkins agent tool contracts"

    $expectedServiceImages = @{
        "adminer" = "adminer:5.3.0-standalone"
        "httpbin" = "mccutchen/go-httpbin:v2.15.0"
        "nginx-web" = "nginx:1.28-alpine"
        "whoami" = "traefik/whoami:v1.10.4"
    }
    $serviceImagesByName = @{}
    foreach ($serviceImage in @($Inventory.ServiceImages)) {
        $serviceImagesByName[[string]$serviceImage.Name] = $serviceImage
    }

    foreach ($serviceName in @($expectedServiceImages.Keys)) {
        Assert-Condition -Condition $serviceImagesByName.ContainsKey($serviceName) -Message ("Dependency inventory should include service image {0}" -f $serviceName)

        $serviceImage = $serviceImagesByName[$serviceName]
        Assert-Equal -Actual ([string]$serviceImage.Category) -Expected "public-image" -Message ("Dependency inventory should classify {0} as a public image" -f $serviceName)
        Assert-Equal -Actual ([string]$serviceImage.ImageReference) -Expected ([string]$expectedServiceImages[$serviceName]) -Message ("Dependency inventory should report the expected image reference for {0}" -f $serviceName)
        Assert-Condition -Condition (-not [bool]$serviceImage.IsDigestPinned) -Message ("Dependency inventory should report {0} as tag-based, not digest-pinned" -f $serviceName)
        Assert-Condition -Condition (-not [bool]$serviceImage.UsesFloatingTag) -Message ("Dependency inventory should not mark versioned service tag for {0} as floating" -f $serviceName)
        Assert-Condition -Condition (-not [bool]$serviceImage.HasJenkinsfile) -Message ("Dependency inventory should keep public service image {0} catalog-only" -f $serviceName)
    }

    $controllerImage = @($Inventory.ControllerImages)[0]
    Assert-Equal -Actual ([string]$controllerImage.ImageReference) -Expected "jenkins/jenkins:lts" -Message "Dependency inventory should report the public controller example image"
    Assert-Equal -Actual ([string]$controllerImage.Tag) -Expected "lts" -Message "Dependency inventory should report the Jenkins controller tag"
    Assert-Condition -Condition (-not [bool]$controllerImage.IsDigestPinned) -Message "Dependency inventory should report the Jenkins LTS example as tag-based"
    Assert-Condition -Condition ([bool]$controllerImage.UsesFloatingTag) -Message "Dependency inventory should flag the floating Jenkins LTS example tag"

    $agentContractsByPath = @{}
    foreach ($contract in @($Inventory.JenkinsAgentToolContracts)) {
        $agentContractsByPath[[string]$contract.SourcePath] = $contract
    }

    foreach ($path in @(
        "jenkins/bundle-delivery.Jenkinsfile",
        "jenkins/bundle-promotion.Jenkinsfile",
        "jenkins/repository-validation.Jenkinsfile"
    )) {
        Assert-Condition -Condition $agentContractsByPath.ContainsKey($path) -Message ("Dependency inventory should include agent tools for {0}" -f $path)
        Assert-ContainsItem -Values @($agentContractsByPath[$path].RequiredTools) -Expected "helm" -Message ("{0} should report helm as a conditional required agent tool" -f $path)
        Assert-ContainsItem -Values @($agentContractsByPath[$path].RequiredTools) -Expected "kubectl" -Message ("{0} should report kubectl as a conditional required agent tool" -f $path)
        Assert-ContainsItem -Values @($agentContractsByPath[$path].OptionalTools) -Expected "git" -Message ("{0} should report git as an optional agent tool" -f $path)
        Assert-ContainsItem -Values @($agentContractsByPath[$path].OptionalTools) -Expected "docker" -Message ("{0} should report docker as an optional agent tool" -f $path)
        Assert-ContainsItem -Values @($agentContractsByPath[$path].OptionalTools) -Expected "python" -Message ("{0} should report python as an optional agent tool" -f $path)
    }

    $seedContract = $agentContractsByPath["jenkins/job-seed.Jenkinsfile"]
    Assert-Condition -Condition ($null -ne $seedContract) -Message "Dependency inventory should include agent tools for the seed Jenkinsfile"
    Assert-Equal -Actual ([int]@($seedContract.RequiredTools).Count) -Expected 0 -Message "Seed job should not require cluster tools"
    Assert-ContainsItem -Values @($seedContract.OptionalTools) -Expected "git" -Message "Seed job should report git as optional"

    $riskText = @($Inventory.RiskIndicators) -join [Environment]::NewLine
    Assert-TextContains `
        -Text $riskText `
        -Expected "No package-manager manifests or lockfiles were found" `
        -Message "Dependency inventory should explain manifest-free dependency posture"
    Assert-TextContains `
        -Text $riskText `
        -Expected "One or more controller image references use a floating tag" `
        -Message "Dependency inventory should explain floating controller image risk"
    Assert-TextContains `
        -Text $riskText `
        -Expected "Public service image references are tag-based" `
        -Message "Dependency inventory should explain tag-based public service image risk"
    Assert-TextContains `
        -Text $riskText `
        -Expected "Jenkins agent tool requirements are declared in checked-in Jenkinsfiles" `
        -Message "Dependency inventory should explain Jenkins agent tool contract risk"
}

function Assert-DependencyInventoryHumanReadableOutput {
    param(
        [string]$Markdown,
        [string]$Text
    )

    Assert-TextContains `
        -Text $Markdown `
        -Expected "| Service | Category | Image | Tag | Floating tag | Digest pinned | Jenkinsfile-backed |" `
        -Message "Markdown dependency inventory should expose service image floating-tag status"
    Assert-TextContains `
        -Text $Markdown `
        -Expected "| adminer | public-image | adminer:5.3.0-standalone | 5.3.0-standalone | False | False | False |" `
        -Message "Markdown dependency inventory should report versioned service tags as non-floating"
    Assert-TextContains `
        -Text $Markdown `
        -Expected "| k8s/jenkins-controller/jenkins.yaml:17 | jenkins/jenkins:lts | lts | True | False |" `
        -Message "Markdown dependency inventory should still flag the floating Jenkins controller image"
    Assert-TextContains `
        -Text $Markdown `
        -Expected "| Source | Profiles | Required tools | Optional tools |" `
        -Message "Markdown dependency inventory should expose Jenkins agent tool contracts"
    Assert-TextContains `
        -Text $Markdown `
        -Expected "| jenkins/bundle-delivery.Jenkinsfile | bundle delivery agent | helm, kubectl | docker, git, python |" `
        -Message "Markdown dependency inventory should report delivery agent tools"

    Assert-TextContains `
        -Text $Text `
        -Expected "adminer: adminer:5.3.0-standalone (tag: 5.3.0-standalone, floating: False, digest pinned: False, Jenkinsfile-backed: False)" `
        -Message "Text dependency inventory should expose service image floating-tag status"
    Assert-TextContains `
        -Text $Text `
        -Expected "k8s/jenkins-controller/jenkins.yaml:17: jenkins/jenkins:lts (tag: lts, floating: True, digest pinned: False)" `
        -Message "Text dependency inventory should still flag the floating Jenkins controller image"
    Assert-TextContains `
        -Text $Text `
        -Expected "jenkins/bundle-delivery.Jenkinsfile: profiles: bundle delivery agent; required: helm, kubectl; optional: docker, git, python" `
        -Message "Text dependency inventory should expose delivery agent tool contracts"
}

function Assert-PresetRuntimeEntrypointsUsePresetValues {
    param(
        [string]$RepositoryValidationScript,
        [string]$BundleDeliveryScript,
        [string]$Root
    )

    $validation = Invoke-JsonScript -ScriptPath $RepositoryValidationScript -Arguments @{
        RepoRoot = $Root
        EnvironmentPreset = @("dev")
        SkipWorkstationValidation = $true
    }
    Assert-Equal -Actual ([string]$validation.Profile) -Expected "web-platform" -Message "Preset-only repository validation should use the dev preset profile"
    Assert-Equal -Actual ([string]$validation.Version) -Expected "0.0.0-dev" -Message "Preset-only repository validation should use the dev preset version"
    Assert-TextContains `
        -Text ([string]$validation.ValuesFile).Replace("\", "/") `
        -Expected "config/platform-values.dev.env.example" `
        -Message "Preset-only repository validation should validate the dev preset values file"

    $delivery = Invoke-JsonScript -ScriptPath $BundleDeliveryScript -Arguments @{
        RepoRoot = $Root
        EnvironmentPreset = @("dev")
        SkipRepositoryValidation = $true
        SkipArchive = $true
        CleanOutput = $true
    }
    Assert-TextContains `
        -Text ([string]$delivery.OutputPath).Replace("\", "/") `
        -Expected "out/delivery/dev" `
        -Message "Preset-only bundle delivery should write to the dev preset output path"

    $manifestPath = Join-Path ([string]$delivery.OutputPath) "bundle-manifest.json"
    Assert-Condition -Condition (Test-Path -Path $manifestPath -PathType Leaf) -Message "Preset-only bundle delivery should write a manifest"
    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    Assert-Equal -Actual ([string]$manifest.Profile) -Expected "web-platform" -Message "Preset-only bundle manifest should use the dev preset profile"
    Assert-Equal -Actual ([string]$manifest.Version) -Expected "0.0.0-dev" -Message "Preset-only bundle manifest should use the dev preset version"
    Assert-Equal -Actual ([string]$manifest.ValuesFile) -Expected "config\platform-values.dev.env.example" -Message "Preset-only bundle manifest should use the dev preset values file"

    $selection = @($manifest.Selections)[0]
    Assert-Equal -Actual ([string]$selection.BundleOutputPath) -Expected "out\delivery\dev" -Message "Preset-only bundle manifest selection should use the dev preset output path"
    Assert-Equal -Actual ([string]$selection.ArchivePath) -Expected "out\delivery\dev.zip" -Message "Preset-only bundle manifest selection should use the dev preset archive path"
}

function Get-PublicPresetDataByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string[]]$Presets
    )

    $presetDataByName = @{}
    foreach ($preset in @($Presets)) {
        $presetPath = Join-Path $Root ("config/environments/{0}.psd1" -f $preset)
        Assert-Condition -Condition (Test-Path -Path $presetPath -PathType Leaf) -Message ("Public preset file should exist: {0}" -f $presetPath)
        $presetDataByName[$preset] = Import-PowerShellDataFile -Path $presetPath
    }

    return $presetDataByName
}

function ConvertTo-ExpectedDslText {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("\", "\\").Replace("'", "\'")
}

function Assert-PublicPresetSelectionMatchesDataFile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Selection,

        [Parameter(Mandatory = $true)]
        [hashtable]$PresetData,

        [Parameter(Mandatory = $true)]
        [string]$Preset
    )

    Assert-Equal -Actual ([string]$Selection.Description) -Expected ([string]$PresetData.Description) -Message ("Preset {0} description should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.Profile) -Expected ([string]$PresetData.Profile) -Message ("Preset {0} profile should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.ValuesFile) -Expected ([string]$PresetData.ValuesFile) -Message ("Preset {0} values file should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.Version) -Expected ([string]$PresetData.Version) -Message ("Preset {0} version should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.BundleOutputPath) -Expected ([string]$PresetData.OutputPath) -Message ("Preset {0} bundle output path should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.ArchivePath) -Expected ([string]$PresetData.ArchivePath) -Message ("Preset {0} archive path should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([string]$Selection.PromotionExtractPath) -Expected ([string]$PresetData.PromotionExtractPath) -Message ("Preset {0} promotion extract path should come from the preset file" -f $Preset)
    Assert-Equal -Actual ([bool]$Selection.IncludeJenkins) -Expected ([bool]$PresetData.IncludeJenkins) -Message ("Preset {0} IncludeJenkins value should come from the preset file" -f $Preset)

    foreach ($application in @(Get-NormalizedList -Values @($PresetData.Applications))) {
        Assert-ContainsItem -Values @($Selection.Applications) -Expected ([string]$application) -Message ("Preset {0} should include application {1} from the preset file" -f $Preset, $application)
        Assert-ContainsItem -Values @($Selection.ServiceDirectories) -Expected ([string]$application) -Message ("Preset {0} service projection should include application {1}" -f $Preset, $application)
    }

    foreach ($dataService in @(Get-NormalizedList -Values @($PresetData.DataServices))) {
        Assert-ContainsItem -Values @($Selection.DataServices) -Expected ([string]$dataService) -Message ("Preset {0} should include data service {1} from the preset file" -f $Preset, $dataService)
    }
}

function Assert-PublicPresetMatrixDslContainsPresetData {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$DslPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$PresetDataByName,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedPresets
    )

    Assert-Condition -Condition (Test-Path -Path $DslPath -PathType Leaf) -Message ("Generated public preset matrix DSL should exist: {0}" -f $DslPath)
    $dsl = Get-Content -Path $DslPath -Raw

    foreach ($preset in @($ExpectedPresets)) {
        Assert-Condition -Condition $PresetDataByName.ContainsKey($preset) -Message ("Preset data should be loaded for {0}" -f $preset)
        $presetData = $PresetDataByName[$preset]
        $selection = @($Plan.Selections | Where-Object { [string]$_.Name -eq $preset })[0]
        Assert-Condition -Condition ($null -ne $selection) -Message ("Public preset matrix should include selection {0}" -f $preset)

        Assert-PublicPresetSelectionMatchesDataFile -Selection $selection -PresetData $presetData -Preset $preset

        $validationJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "repository-validation"
        $deliveryJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-delivery"
        $promotionJob = Get-JenkinsPlanPipelineJob -Selection $selection -Name "bundle-promotion"

        foreach ($expectedText in @(
            ("Generated bundle job folder for selection \'{0}\' using profile \'{1}\'." -f $preset, $presetData.Profile),
            ("Selection: {0}" -f $preset),
            ("Profile: {0}" -f $selection.Profile),
            ("Applications: {0}" -f (Get-TextList -Values @($selection.Applications))),
            ("Data services: {0}" -f (Get-TextList -Values @($selection.DataServices))),
            ("VALIDATION_ENVIRONMENT_PRESET={0}" -f $preset),
            ("VALIDATION_VALUES_FILE={0}" -f (ConvertTo-ExpectedDslText -Value ([string]$presetData.ValuesFile))),
            ("VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY=false"),
            ("BUNDLE_ENVIRONMENT_PRESET={0}" -f $preset),
            ("BUNDLE_OUTPUT_PATH={0}" -f (ConvertTo-ExpectedDslText -Value ([string]$presetData.OutputPath))),
            ("BUNDLE_ARCHIVE_PATH={0}" -f (ConvertTo-ExpectedDslText -Value ([string]$presetData.ArchivePath))),
            ("BUNDLE_DEPLOY=false"),
            ("PROMOTION_ENVIRONMENT_PRESET={0}" -f $preset),
            ("PROMOTION_ARCHIVE_PATH={0}" -f (ConvertTo-ExpectedDslText -Value ([string]$presetData.ArchivePath))),
            ("PROMOTION_EXTRACT_PATH={0}" -f (ConvertTo-ExpectedDslText -Value ([string]$presetData.PromotionExtractPath))),
            ("PROMOTION_DEPLOY=false"),
            ("PROMOTION_DEPLOY_DRY_RUN=true"),
            (ConvertTo-ExpectedDslText -Value ([string]$validationJob.LocalCommand)),
            (ConvertTo-ExpectedDslText -Value ([string]$deliveryJob.LocalCommand)),
            (ConvertTo-ExpectedDslText -Value ([string]$promotionJob.LocalCommand))
        )) {
            Assert-TextContains -Text $dsl -Expected ([string]$expectedText) -Message ("Public preset matrix DSL should include {0} data: {1}" -f $preset, $expectedText)
        }

        Assert-ContainsItem -Values @($deliveryJob.UpstreamDependencies) -Expected ([string]$validationJob.Path) -Message ("Public preset matrix delivery job should depend on validation for {0}" -f $preset)
        Assert-ContainsItem -Values @($promotionJob.UpstreamDependencies) -Expected ([string]$deliveryJob.Path) -Message ("Public preset matrix promotion job should depend on delivery for {0}" -f $preset)
    }
}

$context = Initialize-JenkinsValidationContext `
    -RepoRoot $RepoRoot `
    -DefaultRoot (Join-Path $PSScriptRoot "..") `
    -OutputDirectory "out/jenkins/tests/public-presets"

$root = $context.Root
$jobPlanScript = $context.Paths.JobPlanScript
$jobDslScript = $context.Paths.JobDslScript
$dependencyInventoryScript = $context.Paths.DependencyInventoryScript
$repositoryValidationScript = $context.Paths.RepositoryValidationScript
$bundleDeliveryScript = $context.Paths.BundleDeliveryScript
$bundlePromotionScript = $context.Paths.BundlePromotionScript
$seedJobPath = $context.Paths.SeedJobPath
$deliveryJobPath = $context.Paths.DeliveryJobPath
$promotionJobPath = $context.Paths.PromotionJobPath
$outputDirectory = $context.OutputDirectory
$presets = @($context.Presets)
$servicePlan = $context.ServicePlan
$serviceIndex = $context.ServiceIndex
$presetDataByName = Get-PublicPresetDataByName -Root $root -Presets $presets

Assert-RepoOutputPathCaseBoundary -Root $root
Assert-RepoOutputPathRejectsControlCharacters -Root $root

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

$explicitScmPreset = [string]$presets[0]
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

$httpsScmDslPath = Join-Path $outputDirectory ("{0}-https-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "https://example.invalid/org/repo.git" `
    -BranchSpec "refs/heads/release candidate" `
    -OutputPath $httpsScmDslPath 6>$null | Out-Null
Assert-ScmVariantDsl `
    -DslPath $httpsScmDslPath `
    -ExpectedRepoUrl "https://example.invalid/org/repo.git" `
    -ExpectedBranchSpec "refs/heads/release candidate"

$sshScmDslPath = Join-Path $outputDirectory ("{0}-ssh-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "ssh://git@example.invalid/org/repo.git" `
    -BranchSpec "*/feature/controller-boundary" `
    -ScmCredentialsId "jenkins-controller-scm" `
    -OutputPath $sshScmDslPath 6>$null | Out-Null
Assert-ScmVariantDsl `
    -DslPath $sshScmDslPath `
    -ExpectedRepoUrl "ssh://git@example.invalid/org/repo.git" `
    -ExpectedBranchSpec "*/feature/controller-boundary" `
    -ExpectedScmCredentialsId "jenkins-controller-scm"

$gitSshScmDslPath = Join-Path $outputDirectory ("{0}-git-ssh-scm-seed-job-dsl.groovy" -f $explicitScmPreset)
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $explicitScmPreset `
    -RepoUrl "git+ssh://git@example.invalid/org/repo.git" `
    -BranchSpec "refs/heads/main" `
    -ScmCredentialsId "git-ssh-scm" `
    -OutputPath $gitSshScmDslPath 6>$null | Out-Null
Assert-ScmVariantDsl `
    -DslPath $gitSshScmDslPath `
    -ExpectedRepoUrl "git+ssh://git@example.invalid/org/repo.git" `
    -ExpectedBranchSpec "refs/heads/main" `
    -ExpectedScmCredentialsId "git-ssh-scm"

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobDslScript `
    -Arguments @{
        RepoRoot = $root
        EnvironmentPreset = $explicitScmPreset
        RepoUrl = "https://example.invalid/org/repo with space.git"
        OutputPath = "out/jenkins/tests/public-presets/unsafe-scm-url-whitespace.groovy"
    } `
    -ExpectedMessage "RepoUrl must not contain whitespace." `
    -Message "Job DSL export should reject repository URLs with whitespace"

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

$publicPresetMatrixPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    EnvironmentPreset = $presets
    Format = "json"
}
Assert-PublicPresetMatrixServiceCoverage `
    -Plan $publicPresetMatrixPlan `
    -ExpectedPresets $presets `
    -ServiceIndex $serviceIndex
$publicPresetMatrixDslPath = Join-Path $outputDirectory "public-preset-matrix-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -EnvironmentPreset $presets `
    -OutputPath $publicPresetMatrixDslPath 6>$null | Out-Null
Assert-MultiPresetPlanAndDsl -Plan $publicPresetMatrixPlan -ExpectedPresets $presets -DslPath $publicPresetMatrixDslPath
Assert-PublicPresetMatrixDslContainsPresetData `
    -Plan $publicPresetMatrixPlan `
    -DslPath $publicPresetMatrixDslPath `
    -PresetDataByName $presetDataByName `
    -ExpectedPresets $presets

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

$escapedMetadataDslPath = Join-Path $outputDirectory "escaped-metadata-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "quote safe" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -DataServices @("redis") `
    -ValuesFile "config\quoted'value.env" `
    -DockerRegistry "registry.example.invalid/team\release's" `
    -Version "2.0.0-beta'1" `
    -BundleOutputPath "out\delivery\quoted value" `
    -ArchivePath "out\delivery\quoted bundle's.zip" `
    -PromotionExtractPath "out\promotion\quoted folder" `
    -SkipServiceJobs `
    -OutputPath $escapedMetadataDslPath 6>$null | Out-Null
Assert-EscapedMetadataDsl -DslPath $escapedMetadataDslPath

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

$includeJenkinsBoundaryPlan = Invoke-JsonScript -ScriptPath $jobPlanScript -Arguments @{
    RepoRoot = $root
    SelectionName = "jenkins/controller boundary"
    Profile = "web-platform"
    Applications = @("nginx-web")
    DataServices = @("redis")
    IncludeJenkins = $true
    SkipServiceJobs = $true
    Format = "json"
}
$includeJenkinsBoundaryDslPath = Join-Path $outputDirectory "include-jenkins-boundary-seed-job-dsl.groovy"
& $jobDslScript `
    -RepoRoot $root `
    -SelectionName "jenkins/controller boundary" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -DataServices @("redis") `
    -IncludeJenkins `
    -SkipServiceJobs `
    -OutputPath $includeJenkinsBoundaryDslPath 6>$null | Out-Null
Assert-IncludeJenkinsBoundaryPlanAndDsl -Plan $includeJenkinsBoundaryPlan -DslPath $includeJenkinsBoundaryDslPath

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
    -ScriptPath $jobPlanScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "empty-root"
        Profile = "web-platform"
        JobRoot = ""
        Format = "json"
    } `
    -ExpectedMessage "Jenkins job path must include at least one safe segment." `
    -Message "Job plan generation should reject empty JobRoot values"

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

Invoke-ScriptExpectingFailure `
    -ScriptPath $jobDslScript `
    -Arguments @{
        RepoRoot = $root
        SelectionName = "empty-service-root"
        Profile = "web-platform"
        ServiceJobRoot = ""
        OutputPath = "out/jenkins/tests/public-presets/empty-service-root-seed-job-dsl.groovy"
    } `
    -ExpectedMessage "Jenkins job path must include at least one safe segment." `
    -Message "Job DSL export should reject empty ServiceJobRoot values"

$serviceJobFixture = New-JenkinsServiceJobFixtureContext `
    -Root $root `
    -OutputDirectory $outputDirectory `
    -DslOutputDirectory "out/jenkins/tests"

$serviceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    SelectionName = "service-job-fixture"
    Profile = "web-platform"
    Applications = @("nginx-web")
    Format = "json"
}
Assert-JenkinsServiceJobFixturePlan -Plan $serviceJobFixturePlan

& $serviceJobFixture.JobDslScript `
    -RepoRoot $serviceJobFixture.Root `
    -SelectionName "service-job-fixture" `
    -Profile "web-platform" `
    -Applications @("nginx-web") `
    -OutputPath $serviceJobFixture.ServiceJobDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixture.ServiceJobDslPath -Plan $serviceJobFixturePlan -Preset "service-job-fixture"
Assert-ServiceJobFixtureDsl -Plan $serviceJobFixturePlan -DslPath $serviceJobFixture.ServiceJobDslPath

$sharedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    ServiceJobRoot = $serviceJobFixture.SharedServiceJobRoot
    Format = "json"
}
Assert-JenkinsServiceJobSharedPresetPlan -Plan $sharedServiceJobFixturePlan -ExpectedServiceJobRoot $serviceJobFixture.SharedServiceJobRoot

& $serviceJobFixture.JobDslScript `
    -RepoRoot $serviceJobFixture.Root `
    -EnvironmentPreset @("fixture-alpha", "fixture-beta") `
    -ServiceJobRoot $serviceJobFixture.SharedServiceJobRoot `
    -OutputPath $serviceJobFixture.SharedServiceJobDslOutputPath 6>$null | Out-Null
Assert-GeneratedDsl -DslPath $serviceJobFixture.SharedServiceJobDslPath -Plan $sharedServiceJobFixturePlan -Preset "shared-service-job-fixture"
Assert-ServiceJobSharedPresetDsl -Plan $sharedServiceJobFixturePlan -DslPath $serviceJobFixture.SharedServiceJobDslPath -ExpectedServiceJobRoot $serviceJobFixture.SharedServiceJobRoot

$skippedServiceJobFixturePlan = Invoke-JsonScript -ScriptPath $serviceJobFixture.JobPlanScript -Arguments @{
    RepoRoot = $serviceJobFixture.Root
    EnvironmentPreset = @("fixture-alpha", "fixture-beta")
    SkipServiceJobs = $true
    Format = "json"
}
Assert-JenkinsServiceJobsSkippedPlan -Plan $skippedServiceJobFixturePlan

& $serviceJobFixture.ServiceValidationScript -RepoRoot $serviceJobFixture.Root 6>$null | Out-Null
Assert-MissingServiceJenkinsfileValidationFails -Root $root -OutputDirectory $outputDirectory
Assert-UnsafeServiceCatalogNamesFail -Root $root -OutputDirectory $outputDirectory

$dependencyInventory = Invoke-JsonScript -ScriptPath $dependencyInventoryScript -Arguments @{
    RepoRoot = $root
    Format = "json"
}
Assert-DependencyInventory -Inventory $dependencyInventory
$dependencyInventoryMarkdown = (& $dependencyInventoryScript -RepoRoot $root -Format markdown | Out-String).Trim()
$dependencyInventoryText = (& $dependencyInventoryScript -RepoRoot $root -Format text | Out-String).Trim()
Assert-DependencyInventoryHumanReadableOutput -Markdown $dependencyInventoryMarkdown -Text $dependencyInventoryText
Assert-PresetRuntimeEntrypointsUsePresetValues `
    -RepositoryValidationScript $repositoryValidationScript `
    -BundleDeliveryScript $bundleDeliveryScript `
    -Root $root

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
Assert-PromotionArchiveEntrySafety `
    -PromotionScript $bundlePromotionScript `
    -Root $root `
    -OutputDirectory $outputDirectory
Assert-UnsupportedServiceComposeUpdateFails -Root $root -OutputDirectory $outputDirectory
Assert-PhaseValidationEvidenceContract -Paths $context.Paths

Write-Output ("Jenkins public preset tests passed for presets: {0}" -f ($presets -join ", "))
Write-Output ("Validated service pipeline catalog entries: {0}" -f @($servicePlan.Services).Count)
Write-Output ("Validated explicit SCM escaping fixture: {0}" -f $explicitScmDslPath)
Write-Output "Validated unsafe SCM inputs fail closed before Job DSL generation."
Write-Output ("Validated public-safe HTTPS SCM fixture: {0}" -f $httpsScmDslPath)
Write-Output ("Validated public-safe SSH SCM fixture: {0}" -f $sshScmDslPath)
Write-Output ("Validated public-safe git+ssh SCM fixture: {0}" -f $gitSshScmDslPath)
Write-Output "Validated whitespace-bearing SCM URLs fail closed before Job DSL generation."
Write-Output ("Validated multi-preset Job DSL fixture: {0}" -f $multiPresetDslPath)
Write-Output ("Validated full public preset matrix fixture: {0}" -f $publicPresetMatrixDslPath)
Write-Output "Validated full public preset service catalog coverage."
Write-Output ("Validated custom direct-selection Job DSL fixture: {0}" -f $customDirectSelectionDslPath)
Write-Output ("Validated SelectionName-only Job DSL fixture: {0}" -f $selectionNameOnlyDslPath)
Write-Output ("Validated escaped metadata Job DSL fixture: {0}" -f $escapedMetadataDslPath)
Write-Output ("Validated nested Job DSL root fixture: {0}" -f $nestedRootDslPath)
Write-Output ("Validated IncludeJenkins opt-in boundary fixture: {0}" -f $includeJenkinsBoundaryDslPath)
Write-Output "Validated unsafe and empty Job DSL root segments fail closed."
Write-Output ("Validated Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixture.ServiceJobDslPath)
Write-Output ("Validated shared Jenkinsfile-backed service job fixture: {0}" -f $serviceJobFixture.SharedServiceJobDslPath)
Write-Output "Validated SkipServiceJobs suppresses Jenkinsfile-backed service jobs."
Write-Output "Validated missing Jenkinsfile-backed service jobs fail closed."
Write-Output "Validated public preset application service catalog coverage."
Write-Output "Validated dependency inventory risk indicators."
Write-Output "Validated seed job SCM apply and destructive delete confirmation guards."
Write-Output "Validated Jenkins artifact archive paths stay under literal out/ paths."
Write-Output "Validated repository output paths reject case-variant out roots."
Write-Output "Validated repository output paths reject control characters."
Write-Output "Validated non-dry-run delivery and promotion deployment approval guards."
Write-Output "Validated promotion archive entries fail closed before extraction."
Write-Output "Validated committed Jenkins runtime entrypoints and public-safe values defaults."
Write-Output "Validated unsupported service ComposeUpdate values fail closed."
Write-Output "Validated phase validation evidence contract."
