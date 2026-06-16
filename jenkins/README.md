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
[`docs/troubleshooting.md`](../docs/troubleshooting.md). For the maintenance
checklist that maps presets, service catalog changes, Job DSL export, and
Jenkinsfiles to validation commands, see
[`docs/maintenance.md`](../docs/maintenance.md). For a focused map of Job DSL,
Pipeline DSL, service catalog, and controller/JCasC ownership, see
[`docs/pipeline-boundaries.md`](../docs/pipeline-boundaries.md).

## Important Defaults

- The default sample applications use public images, so per-service image build jobs are not required.
- Service-level jobs appear only if a service actually has its own Jenkinsfile and the catalog marks it as such.
- `job-seed.Jenkinsfile` leaves the preset list blank by default, which means "use every preset currently found in `config/environments`".
- `job-seed.Jenkinsfile` treats `SEED_SELECTION_NAME` without
  `SEED_ENVIRONMENT_PRESETS` as one custom selection using public-safe defaults.
- `job-seed.Jenkinsfile` leaves the SCM URL and branch spec blank by default. Generated DSL uses public-safe placeholders until you provide `SEED_REPO_URL` and `SEED_BRANCH_SPEC`.
- `job-seed.Jenkinsfile` requires `SEED_CONFIRM_REMOVED_JOB_DELETE=true` before `SEED_APPLY_JOB_DSL=true` can run with `SEED_REMOVED_JOB_ACTION=DELETE`.
- Non-dry-run delivery and promotion deployments require a Jenkins approval prompt and bootstrap secret/status checks.
- `validate-jenkins-job-dsl.ps1` validates job planning, generated Job DSL, SCM placeholder safety, service catalog metadata, committed runtime helper scripts, and public-safe values defaults without contacting a Jenkins controller.
- Generated local command fields describe the Pipeline DSL entrypoint contract; the checked-in runtime helpers can validate inputs and write or verify a controller-free contract bundle under `out/`.
- Live validation, delivery, and promotion still require private values, credentials, registry access, cluster context, and any downstream non-dry-run deployment implementation outside this public template.

Before applying generated DSL in Jenkins, set:

- `SEED_REPO_URL`
- `SEED_BRANCH_SPEC`, such as `*/main` or `*/release/*`
- `SEED_SCM_CREDENTIALS_ID` when the repository requires Jenkins SCM credentials; leave it blank for public repositories
- optional folder roots such as `SEED_JOB_ROOT`

The template intentionally does not assume `main`, `master`, or a fixed protected-branch policy. Keep the branch spec explicit for the repository that will own the generated jobs.
Use an HTTPS/SSH repository URI or a Git scp-like path such as `git@example.invalid:org/repo.git`; local file URLs and relative repository paths are rejected before generated DSL is applied.

## Seed Parameters

| Parameter | Purpose |
| --- | --- |
| `SEED_ENVIRONMENT_PRESETS` | Optional comma-separated preset list. Leave blank to generate every preset from `config/environments`. |
| `SEED_SELECTION_NAME`, `SEED_PROFILE`, `SEED_APPLICATIONS`, `SEED_DATA_SERVICES` | Custom selection inputs used when you are not generating from named presets. `SEED_SELECTION_NAME` alone creates one custom selection with default profile, applications, data services, values file, and output paths. |
| `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, `SEED_SCM_CREDENTIALS_ID` | SCM inputs consumed by generated pipeline jobs. URL and branch spec are required before `SEED_APPLY_JOB_DSL=true`; credentials ID stays optional and parameterized. |
| `SEED_JOB_ROOT`, `SEED_SERVICE_JOB_ROOT` | Jenkins folder roots for bundle jobs and service image jobs. |
| `SEED_SKIP_SERVICE_JOBS` | Generate only the validation, delivery, and promotion bundle chain. |
| `SEED_USE_LIGHTWEIGHT_CHECKOUT` | Controls lightweight checkout in generated SCM-backed pipeline jobs. |
| `SEED_APPLY_JOB_DSL`, `SEED_REMOVED_JOB_ACTION`, `SEED_CONFIRM_REMOVED_JOB_DELETE` | Applies the generated DSL through the Job DSL plugin and controls behavior for previously generated jobs. `DELETE` requires the confirmation parameter. |

## Job DSL Coverage

`scripts/validate-jenkins-job-dsl.ps1` covers the built-in public-safe preset matrix by default. For each preset it:

- renders the Jenkins job plan
- exports ignored Job DSL fixtures under `out/jenkins/validation`
- verifies the validation, delivery, and promotion `pipelineJob` entries
- verifies validation-to-delivery-to-promotion upstream dependencies
- verifies Jenkinsfile-backed selected services are projected into service jobs
- verifies shared Jenkinsfile-backed service jobs are de-duplicated across
  multiple selected presets, including nested service roots
- verifies `SEED_SKIP_SERVICE_JOBS`/`-SkipServiceJobs` suppresses generated
  service jobs even when selected services are Jenkinsfile-backed
- verifies `SEED_SELECTION_NAME`/`-SelectionName` alone creates one custom
  selection instead of falling back to every preset
- verifies generated SCM URL, branch spec, and credentials handling stay parameterized
- verifies explicit SCM URL, branch spec, and credentials values are escaped in generated Groovy
- verifies embedded SCM credentials, unsupported or local repository paths, and control-character inputs fail before Job DSL generation
- verifies destructive removed-job deletion requires explicit seed confirmation
- verifies the seed job passes typed exporter boolean arguments such as lightweight checkout
- validates service catalog metadata and runs the service pipeline validator
- verifies committed runtime helper scripts and public-safe values defaults

This is a controller-free regression fixture. It does not prove a live Jenkins
controller has the Job DSL plugin installed or that private cluster deployment
is ready.

The phase transition wrapper, `scripts/run-phase-validation.sh`, runs the focused
`dev` dashboard commands, this aggregate harness, and
`tests/jenkins-job-dsl.public-presets.ps1` so transition checks exercise the
public default path, the full public-safe preset matrix, custom selection path
safety, and runtime contract files.
Use [`docs/maintenance.md`](../docs/maintenance.md) when selecting the narrower
validation lane for a preset, service catalog, Job DSL, Jenkinsfile, or
controller/JCasC documentation change. Use
[`docs/pipeline-boundaries.md`](../docs/pipeline-boundaries.md) before moving a
responsibility from generated Job DSL into Jenkinsfiles or from Jenkinsfiles into
controller/JCasC rollout work.

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
