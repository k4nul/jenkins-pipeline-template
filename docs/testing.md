# Testing And Validation

This repository uses controller-free PowerShell checks as the first validation
lane for Jenkins job planning, generated Job DSL, and the service pipeline
catalog. The commands below do not contact a live Jenkins controller.

## Prerequisite

Install PowerShell 7 or newer so `pwsh` is available on your shell path.

## Full Local Harness

Run the aggregate harness before changing job planning, Job DSL export,
environment presets, profiles, or service pipeline catalog data:

```powershell
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

The harness validates every preset in `config/environments`, exports ignored
fixtures under `out/jenkins/validation`, checks that generated SCM URL, branch
spec, and credentials handling stay parameterized, verifies explicit seed SCM
inputs are escaped in generated Groovy strings, verifies the generated
validation-delivery-promotion dependency chain, verifies service-job projection
for any Jenkinsfile-backed selected services, verifies destructive removed-job
deletion requires explicit seed confirmation, verifies Jenkins artifact
archiving uses literal paths under `out/`, validates service catalog metadata
and required service file paths, and runs service pipeline validation.

## Dashboard Validation Commands

These commands match the repository's public-safe validation gate for the `dev`
preset. Automation should call the repository-owned wrapper so non-interactive
shells can resolve PowerShell from `PATH`, `POWERSHELL_BIN`, `PWSH`, or common
local install paths:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper runs the phase-gate commands first, then the full public preset
matrix harness:

```powershell
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
```

The final aggregate command validates every built-in public-safe preset and
writes generated fixtures under `out/jenkins/validation`. Generated output must
stay under `out/`, which is ignored by Git. Do not commit generated Job DSL from
a real controller or environment.

## Phase-Ready Job DSL Evidence

The `job-dsl-coverage` phase is ready to hand off only when the controller-free
wrapper passes end to end:

```sh
sh scripts/run-phase-validation.sh
```

That passing result means the local harness has evidence for the focused `dev`
dashboard lane and the full public-safe preset matrix:

- `dev` job planning renders one bundle selection with validation, delivery,
  and promotion jobs under the `platform/dev` folder.
- The service pipeline plan can render the public service catalog without a
  `services/` directory because the built-in services are public-image examples
  and do not declare Jenkinsfile-backed jobs.
- Job DSL export can create the seed fixture under `out/jenkins/` while keeping
  repository URL, branch spec, and credentials ID values parameterized.
- Service pipeline validation and the aggregate Job DSL harness both pass
  without contacting a Jenkins controller.

Use this evidence as a boundary, not as live-controller approval. The wrapper
does not install Jenkins plugins, verify JCasC, create credentials, check agent
tool images, or run delivery/promotion against a cluster. Those are
`pipeline-boundary-hardening` and controller rollout concerns.

When a documentation-only change explains these boundaries, rerun the wrapper if
the wording describes command behavior, generated job topology, or phase
readiness. For prose that only links existing runbooks together, a Markdown
review plus `git diff --check` is sufficient.

## Service Pipeline Catalog-Only Gate

`scripts/validate-service-pipelines.ps1` supports the current public template
state where `config/service-pipelines.psd1` lists public-image examples but no
`services/` directory is present. In that case the command passes only when the
catalog has no Jenkinsfile-backed service jobs. If a catalog entry sets
`HasJenkinsfile = $true` or defines required Jenkinsfile text assertions, add the
matching `services/<name>/Jenkinsfile` and required files before expecting this
gate to pass.

## What These Checks Prove

- The `dev`, `staging`, and `prod` presets can render Jenkins job plans.
- Job DSL export can produce folder and `pipelineJob` definitions.
- The phase gate exercises both the focused `dev` transition commands and the
  all-preset public Job DSL harness.
- Generated bundle jobs preserve the validation, delivery, manual approval, and
  promotion dependency order.
- Generated SCM URL, branch spec, and credentials ID values remain placeholders
  or parameters until a Jenkins seed job receives explicit values.
- Explicit seed SCM URL, branch spec, and credentials ID values are emitted as
  escaped Groovy strings while generated jobs still call `credentials(scmCredentialsId)`
  and `branch(branchSpec)`.
- Applying generated Job DSL with `SEED_REMOVED_JOB_ACTION=DELETE` requires the
  separate `SEED_CONFIRM_REMOVED_JOB_DELETE` guard.
- Jenkins artifact archive paths are literal workspace-relative paths under
  `out/`, not caller-controlled absolute paths, parent traversal, or Ant globs.
- Service catalog required-file paths are relative service-local paths, not
  absolute paths, parent traversal, or glob patterns.
- Service catalog entries remain public-safe and internally consistent.
- Jenkinsfile-backed catalog services selected by a preset are projected into
  generated service jobs with service-local Jenkinsfile paths.

## What These Checks Do Not Prove

- A live Jenkins controller has the required Job DSL plugin or JCasC setup.
- Jenkins agents have `kubectl`, `helm`, registry access, or cluster access.
- Runtime entrypoint scripts and config files referenced by Jenkinsfiles exist
  for a controller deployment.
- Non-dry-run delivery and promotion can run without manual approval.

Review [jenkins/JOB_BLUEPRINT.md](../jenkins/JOB_BLUEPRINT.md) before changing
the Job DSL, Pipeline DSL, JCasC, or preset responsibility boundaries.
Use [maintenance.md](maintenance.md) for the change-lane checklist that maps
presets, profiles, service catalog entries, Job DSL export, Jenkinsfiles, and
controller/JCasC scope to their validation commands.
