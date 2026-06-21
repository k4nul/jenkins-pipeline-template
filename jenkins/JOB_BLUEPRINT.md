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
- Providing `SEED_SELECTION_NAME` without environment presets generates one
  custom selection with public-safe defaults instead of the full preset matrix.
- `SEED_REPO_URL` and `SEED_BRANCH_SPEC` default to blank in `job-seed.Jenkinsfile`.
- Generated DSL uses public-safe SCM placeholders unless `SEED_REPO_URL` and `SEED_BRANCH_SPEC` are provided.
- If you apply the generated DSL in Jenkins, set `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, and any required `SEED_SCM_CREDENTIALS_ID` first so SCM-backed jobs point at your intended repository.
- If you provide `SEED_DOCKER_REGISTRY`, treat it as environment-specific metadata. The seed job will skip generated Job DSL artifact archival when concrete SCM, registry, or credential metadata is present.
- Keep `SEED_JOB_ROOT` and `SEED_SERVICE_JOB_ROOT` as non-empty Jenkins folder paths made from safe literal segments. Blank roots, parent traversal, and expression-like folder segments fail before Job DSL generation.
- Service pipeline validation runs before service-job generation unless `SEED_SKIP_SERVICE_JOBS=true`.

## Responsibility Boundaries

This section is the reader-facing anchor for `pipeline-boundary-hardening`: keep
Job DSL generation, Pipeline DSL execution, service catalog metadata, and live
controller/JCasC rollout separate even when the same seed job connects them in a
Jenkins controller.

- Job DSL owns folder and job creation. Keep generated folder paths, SCM URL, branch spec, credentials ID, lightweight checkout, and artifact retention in `scripts/export-jenkins-job-dsl.ps1` and `jenkins/job-seed.Jenkinsfile`.
- Pipeline DSL owns execution flow. Keep validation, delivery, promotion, approval, archive, and safety gate behavior in the Jenkinsfiles under `jenkins/`.
- Jenkins Configuration as Code (JCasC) owns controller and plugin installation. Keep controller plugins, global credentials providers, agents, and security realm configuration outside this reusable template unless they are represented as public-safe examples.
- Environment presets own reusable parameter defaults. Keep preset-specific profile, service, version, output, and archive defaults in `config/environments/*.psd1` so generated Job DSL and Pipeline DSL consume the same source of truth.

Do not move private controller settings, fixed branch policies, or real credentials IDs into Job DSL or Pipeline DSL. When a future JCasC package is added, validate it separately from the controller-free plan/export checks below.

## Controller-Free Regression Strategy

Use the local phase wrapper and PowerShell scripts as the first regression
fixture before changing Jenkins plugin assumptions, public image versions, or
generated pipeline topology:

```text
sh scripts/run-phase-validation.sh
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -OutputPath out/jenkins/public-preset-matrix-seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
```

`run-phase-validation.sh` is the transition gate and calls the focused `dev`
commands, dependency inventory, the aggregate harness, and the public preset
test suite. It labels each wrapper step, reports the first failing command and
exit code, and is the same command used by the `Jenkins Phase Validation`
GitHub Actions workflow. Generated `out/jenkins/**` workflow artifacts are
diagnostic fixtures only and stay out of Git.
`validate-jenkins-job-dsl.ps1` is the aggregate controller-free harness. By
default it validates every built-in environment preset, exports ignored DSL
fixtures under `out/jenkins/validation`, exports one combined full public preset
matrix fixture, checks generated `pipelineJob` entries, verifies SCM
URL/branch/credentials values remain parameterized, exercises explicit SCM value
escaping in generated Groovy, verifies destructive
removed-job deletion requires explicit seed confirmation, validates
validation-to-delivery-to-promotion dependencies, verifies Jenkinsfile-backed
service job projection with a synthetic fixture, verifies public preset
applications are covered by service pipeline catalog metadata, verifies
catalog-only public-image services do not generate Jenkins service jobs,
verifies shared Jenkinsfile-backed service jobs are de-duplicated across
multiple selected presets and nested service roots, verifies `-SkipServiceJobs`
suppresses those generated service jobs when requested, verifies the seed job
preflights service pipeline validation before generating service jobs, verifies
the seed job passes typed exporter boolean arguments, verifies generated Job DSL
artifact archival is skipped when concrete SCM, registry, or credential
metadata is present,
checks that Jenkinsfile-backed service entries fail closed when
`services/<name>/Jenkinsfile` is missing, validates service catalog metadata, and
runs service pipeline validation. The public preset test suite adds custom
selection, `SEED_SELECTION_NAME`-only defaults, nested job-root, unsafe or empty
root rejection, and runtime argument splatting coverage.

This fixture is intentionally controller-free. Treat it as a pipeline unit test
lane for generated command arguments, public-safe SCM placeholders, service
catalog coverage, generated Job DSL structure, and public-safe runtime contract
files. It does not prove that a live Jenkins controller has the Job DSL plugin
installed or that private non-dry-run deployment is ready. Add
JenkinsPipelineUnit tests only when scripted or shared-library logic grows
beyond the current declarative Jenkinsfile wrappers.

For the exact local command lane and common failure interpretation, see
[`docs/testing.md`](../docs/testing.md) and
[`docs/troubleshooting.md`](../docs/troubleshooting.md).

## Preset Matrix

The default preset matrix covers `dev`, `staging`, and `prod`.

| Preset | Profile | Applications | Data services | Jenkins components | Verification command |
| --- | --- | --- | --- | --- | --- |
| `dev` | `web-platform` | `nginx-web`, `httpbin`, `whoami` | `redis` | excluded | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -EnvironmentPreset dev` |
| `staging` | `shared-services` | `nginx-web`, `httpbin`, `adminer` | `postgresql`, `redis` | excluded | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -EnvironmentPreset staging` |
| `prod` | `shared-services` | `nginx-web`, `whoami` | `postgresql`, `redis` | excluded | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -EnvironmentPreset prod` |

Run `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` for the full
preset matrix when a change touches `config/environments/`,
`config/profiles/`, `config/service-pipelines.psd1`,
`scripts/show-jenkins-job-plan.ps1`, or `scripts/export-jenkins-job-dsl.ps1`.
The no-`EnvironmentPreset` plan/export path is the full matrix path. Keep
`out/` generated files ignored and review generated Job DSL before applying it
to a controller.

## Dependency Upgrade Lanes

- Public image catalog updates belong in `config/service-pipelines.psd1` and should be validated with `scripts/show-service-pipeline-plan.ps1` plus `scripts/validate-service-pipelines.ps1`.
- Jenkins plugin or controller dependency changes belong in a future JCasC package and should not change generated Job DSL defaults until the controller plugin set is documented.
- PowerShell runtime compatibility changes should be proven by the controller-free regression strategy on a current `pwsh` runtime before Jenkins agent images are updated.
- Jenkinsfile behavior changes should preserve manual approval for non-dry-run deployment and promotion paths.

Use [docs/dependency-plan.md](../docs/dependency-plan.md) for the staged
dependency and toolchain upgrade plan before changing image tags, controller
runtime assumptions, Jenkins plugins, or agent tool baselines.

## Optional Service Jobs

The current public-image sample services do not require dedicated Jenkins build jobs.

If you later add your own custom services with Jenkinsfiles, regenerate the plan and seed DSL so those service jobs appear automatically.
