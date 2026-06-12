# Jenkins

English | [한국어](README.ko.md)

This directory contains generic Jenkins automation for the repository itself. It is designed for repository-level workflows rather than company-specific application pipelines.

## Main Jobs

- `repository-validation.Jenkinsfile`: validates repository structure and rendered assets
- `bundle-delivery.Jenkinsfile`: renders, validates, and archives a bundle
- `bundle-promotion.Jenkinsfile`: re-validates and optionally deploys an archived bundle
- `job-seed.Jenkinsfile`: generates Jenkins folders and pipeline jobs from the shared job plan

## What You Need In Jenkins

The Jenkins agent should have:

- PowerShell or `pwsh`
- `git`
- `kubectl` for cluster-aware validation and manifest workflows
- `helm` for Helm-managed components

Each Jenkinsfile starts with an agent-readiness preflight so missing tools fail early with a clearer message.

## Typical Jenkins Setup Flow

1. Preview the repository-level job plan:

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
```

2. Run the controller-free Job DSL regression harness:

```powershell
.\scripts\validate-jenkins-job-dsl.ps1
```

3. Generate Job DSL:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

4. Review the generated DSL and SCM settings.
5. Apply the DSL in Jenkins.
6. Run `repository-validation` before enabling delivery or promotion for a team.

For local validation details and known controller-free limits, see
[`docs/testing.md`](../docs/testing.md) and
[`docs/troubleshooting.md`](../docs/troubleshooting.md).

## Important Defaults

- The default sample applications use public images, so per-service image build jobs are not required.
- Service-level jobs appear only if a service actually has its own Jenkinsfile and the catalog marks it as such.
- `job-seed.Jenkinsfile` leaves the preset list blank by default, which means "use every preset currently found in `config/environments`".
- `job-seed.Jenkinsfile` leaves the SCM URL and branch spec blank by default. Generated DSL uses public-safe placeholders until you provide `SEED_REPO_URL` and `SEED_BRANCH_SPEC`.
- Non-dry-run delivery and promotion deployments require a Jenkins approval prompt and bootstrap secret/status checks.
- `validate-jenkins-job-dsl.ps1` validates job planning, generated Job DSL, SCM placeholder safety, and service catalog metadata without contacting a Jenkins controller.
- Generated local command fields describe the Pipeline DSL entrypoint contract; the controller-free harness does not execute live validation, delivery, or promotion entrypoints.
- Live validation, delivery, and promotion jobs require the runtime helper scripts and environment value files referenced by the Jenkinsfiles to exist in the target repository or seed workspace.

Before applying generated DSL in Jenkins, set:

- `SEED_REPO_URL`
- `SEED_BRANCH_SPEC`, such as `*/main` or `*/release/*`
- `SEED_SCM_CREDENTIALS_ID` when the repository requires Jenkins SCM credentials; leave it blank for public repositories
- optional folder roots such as `SEED_JOB_ROOT`

The template intentionally does not assume `main`, `master`, or a fixed protected-branch policy. Keep the branch spec explicit for the repository that will own the generated jobs.

## Seed Parameters

| Parameter | Purpose |
| --- | --- |
| `SEED_ENVIRONMENT_PRESETS` | Optional comma-separated preset list. Leave blank to generate every preset from `config/environments`. |
| `SEED_SELECTION_NAME`, `SEED_PROFILE`, `SEED_APPLICATIONS`, `SEED_DATA_SERVICES` | Custom selection inputs used when you are not generating from named presets. |
| `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, `SEED_SCM_CREDENTIALS_ID` | SCM inputs consumed by generated pipeline jobs. URL and branch spec are required before `SEED_APPLY_JOB_DSL=true`; credentials ID stays optional and parameterized. |
| `SEED_JOB_ROOT`, `SEED_SERVICE_JOB_ROOT` | Jenkins folder roots for bundle jobs and service image jobs. |
| `SEED_SKIP_SERVICE_JOBS` | Generate only the validation, delivery, and promotion bundle chain. |
| `SEED_USE_LIGHTWEIGHT_CHECKOUT` | Controls lightweight checkout in generated SCM-backed pipeline jobs. |
| `SEED_APPLY_JOB_DSL`, `SEED_REMOVED_JOB_ACTION` | Applies the generated DSL through the Job DSL plugin and controls behavior for previously generated jobs. |

## Job DSL Coverage

`scripts/validate-jenkins-job-dsl.ps1` covers the built-in public-safe preset matrix by default. For each preset it:

- renders the Jenkins job plan
- exports ignored Job DSL fixtures under `out/jenkins/validation`
- verifies the validation, delivery, and promotion `pipelineJob` entries
- verifies generated SCM URL, branch spec, and credentials handling stay parameterized
- validates service catalog metadata and runs the service pipeline validator

This is a controller-free regression fixture. It does not prove a live Jenkins controller has the Job DSL plugin installed or that the runtime validation, delivery, and promotion entrypoints are complete.

## Custom Selection Example

If you want a custom selection instead of environment presets:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 `
  -SelectionName sandbox `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -RepoUrl https://github.com/example-org/example-repo.git `
  -BranchSpec '*/<branch-or-pattern>' `
  -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

See also:

- `JOB_BLUEPRINT.md`
- `scripts/show-jenkins-job-plan.ps1`
- `scripts/export-jenkins-job-dsl.ps1`
