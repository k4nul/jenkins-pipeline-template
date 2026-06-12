# Jenkins Job Blueprint

Recommended generic folder layout:

```text
platform/
  dev/
    repository-validation
    bundle-delivery
    bundle-promotion
  staging/
    repository-validation
    bundle-delivery
    bundle-promotion
  prod/
    repository-validation
    bundle-delivery
    bundle-promotion
```

## Why This Layout

- repository-level jobs stay stable even if application examples change
- delivery and promotion stay clearly separated
- environment presets map cleanly to job folders
- The folder names above are only examples. If your teams use names such as `sandbox`, `qa`, or `production`, the same layout still applies.

## Seeding Defaults

- Leaving `SEED_ENVIRONMENT_PRESETS` blank in `job-seed.Jenkinsfile` will generate jobs for every preset currently present in `config/environments`.
- `SEED_REPO_URL` and `SEED_BRANCH_SPEC` default to blank in `job-seed.Jenkinsfile`.
- Generated DSL uses public-safe SCM placeholders unless `SEED_REPO_URL` and `SEED_BRANCH_SPEC` are provided.
- If you apply the generated DSL in Jenkins, set `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, and any required `SEED_SCM_CREDENTIALS_ID` first so SCM-backed jobs point at your intended repository.

## Responsibility Boundaries

- Job DSL owns folder and job creation. Keep generated folder paths, SCM URL, branch spec, credentials ID, lightweight checkout, and artifact retention in `scripts/export-jenkins-job-dsl.ps1` and `jenkins/job-seed.Jenkinsfile`.
- Pipeline DSL owns execution flow. Keep validation, delivery, promotion, approval, archive, and safety gate behavior in the Jenkinsfiles under `jenkins/`.
- Jenkins Configuration as Code (JCasC) owns controller and plugin installation. Keep controller plugins, global credentials providers, agents, and security realm configuration outside this reusable template unless they are represented as public-safe examples.
- Environment presets own reusable parameter defaults. Keep preset-specific profile, service, version, output, and archive defaults in `config/environments/*.psd1` so generated Job DSL and Pipeline DSL consume the same source of truth.

Do not move private controller settings, fixed branch policies, or real credentials IDs into Job DSL or Pipeline DSL. When a future JCasC package is added, validate it separately from the controller-free plan/export checks below.

## Controller-Free Regression Strategy

Use the local PowerShell scripts as the first regression fixture before changing Jenkins plugin assumptions, public image versions, or generated pipeline topology:

```powershell
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
```

This fixture is intentionally controller-free. Treat it as a pipeline unit test lane for generated command arguments, public-safe SCM placeholders, service catalog coverage, and generated Job DSL structure. Add JenkinsPipelineUnit tests only when scripted or shared-library logic grows beyond the current declarative Jenkinsfile wrappers.

## Preset Matrix

The default preset matrix covers `dev`, `staging`, and `prod`.

| Preset | Profile | Applications | Data services | Jenkins components | Verification command |
| --- | --- | --- | --- | --- | --- |
| `dev` | `web-platform` | `nginx-web`, `httpbin`, `whoami` | `redis` | excluded | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json` |
| `staging` | `shared-services` | `nginx-web`, `httpbin`, `adminer` | `postgresql`, `redis` | excluded | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset staging -Format json` |
| `prod` | `shared-services` | `nginx-web`, `whoami` | `postgresql`, `redis` | excluded | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset prod -Format json` |

Run the full preset matrix when a change touches `config/environments/`, `config/profiles/`, `config/service-pipelines.psd1`, `scripts/show-jenkins-job-plan.ps1`, or `scripts/export-jenkins-job-dsl.ps1`. Keep `out/` generated files ignored and review generated Job DSL before applying it to a controller.

## Dependency Upgrade Lanes

- Public image catalog updates belong in `config/service-pipelines.psd1` and should be validated with `scripts/show-service-pipeline-plan.ps1` plus `scripts/validate-service-pipelines.ps1`.
- Jenkins plugin or controller dependency changes belong in a future JCasC package and should not change generated Job DSL defaults until the controller plugin set is documented.
- PowerShell runtime compatibility changes should be proven by the controller-free regression strategy on a current `pwsh` runtime before Jenkins agent images are updated.
- Jenkinsfile behavior changes should preserve manual approval for non-dry-run deployment and promotion paths.

## Optional Service Jobs

The current public-image sample services do not require dedicated Jenkins build jobs.

If you later add your own custom services with Jenkinsfiles, regenerate the plan and seed DSL so those service jobs appear automatically.
