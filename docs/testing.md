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
inputs are escaped in generated Groovy strings, verifies destructive removed-job
deletion requires explicit seed confirmation, validates service catalog metadata,
and runs service pipeline validation.

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
- Generated SCM URL, branch spec, and credentials ID values remain placeholders
  or parameters until a Jenkins seed job receives explicit values.
- Explicit seed SCM URL, branch spec, and credentials ID values are emitted as
  escaped Groovy strings while generated jobs still call `credentials(scmCredentialsId)`
  and `branch(branchSpec)`.
- Applying generated Job DSL with `SEED_REMOVED_JOB_ACTION=DELETE` requires the
  separate `SEED_CONFIRM_REMOVED_JOB_DELETE` guard.
- Service catalog entries remain public-safe and internally consistent.

## What These Checks Do Not Prove

- A live Jenkins controller has the required Job DSL plugin or JCasC setup.
- Jenkins agents have `kubectl`, `helm`, registry access, or cluster access.
- Runtime entrypoint scripts and config files referenced by Jenkinsfiles exist
  for a controller deployment.
- Non-dry-run delivery and promotion can run without manual approval.

Review [jenkins/JOB_BLUEPRINT.md](../jenkins/JOB_BLUEPRINT.md) before changing
the Job DSL, Pipeline DSL, JCasC, or preset responsibility boundaries.
