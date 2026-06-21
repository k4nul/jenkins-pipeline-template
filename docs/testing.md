# Testing And Validation

This repository uses controller-free PowerShell checks as the first validation
lane for Jenkins job planning, generated Job DSL, and the service pipeline
catalog. The commands below do not contact a live Jenkins controller.

## Prerequisite

Install PowerShell 7 or newer so `pwsh` is available on your shell path.
For first-time setup and the recommended read order across the local runbooks,
start with [onboarding.md](onboarding.md).

## Full Local Harness

Run the aggregate harness before changing job planning, Job DSL export,
environment presets, profiles, or service pipeline catalog data:

```powershell
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

The harness validates every preset in `config/environments`, exports ignored
fixtures under `out/jenkins/validation`, exports one combined full public preset
matrix fixture, checks that generated SCM URL, branch spec, and credentials
handling stay parameterized, verifies explicit seed SCM inputs are escaped in
generated Groovy strings, verifies the generated validation-delivery-promotion
dependency chain, verifies service-job projection with synthetic
Jenkinsfile-backed service fixtures, verifies every public preset application is
covered by service pipeline catalog metadata, verifies catalog-only public-image
services do not produce Jenkins service jobs, verifies shared service-job
de-duplication across multiple selected presets and nested service roots,
verifies `-SkipServiceJobs` suppresses Jenkinsfile-backed service jobs, verifies
`-SelectionName` by itself creates one custom selection with public-safe
defaults instead of falling back to the full preset matrix, verifies
empty or unsafe generated Job DSL roots fail closed before folder or job
creation,
destructive removed-job deletion requires explicit seed confirmation, verifies
Job DSL apply still requires concrete SCM URL and branch inputs, verifies
the seed job passes typed exporter boolean arguments, verifies seed-generated
Job DSL artifacts are not archived when concrete SCM, registry, or credential
metadata is supplied, verifies Jenkins artifact archiving uses literal paths
under `out/`, verifies non-dry-run delivery and promotion stay behind approval
and public-safe helper guardrails, verifies the committed runtime helper scripts
and tracked public-safe values defaults exist, validates service catalog metadata
and required service file paths,
verifies Jenkinsfile-backed catalog entries fail closed when
`services/<name>/Jenkinsfile` is missing, and runs service pipeline validation.

## Dashboard Validation Commands

These commands match the repository's public-safe validation gate for the `dev`
preset. Automation should call the repository-owned wrapper so non-interactive
shells can resolve PowerShell from `PATH`, `POWERSHELL_BIN`, `PWSH`, or common
local install paths:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper runs the phase-gate commands first, then the full public preset
matrix harness and the extended public preset test suite:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
```

The wrapper prints the resolved PowerShell path and labeled step boundaries to
stderr before each command. If a step fails, the first failing label, exit code,
and command are reported before the wrapper exits with that command's status.
Use that first failed label as the dashboard blocker instead of rerunning a
different subset of checks.

The final aggregate command validates every built-in public-safe preset
individually, then validates a single combined public preset matrix Job DSL
fixture. Generated output must stay under `out/`, which is ignored by Git. Job
DSL fixture content is deterministic and the writer skips unchanged files, so
repeated validation runs do not rewrite ignored artifacts just because the
command was re-run. Do not commit generated Job DSL from a real controller or
environment.

The same wrapper is also wired into
`.github/workflows/phase-validation.yml` for pull requests, pushes, and manual
workflow dispatch. That workflow is controller-free: it checks out the
repository, shows the hosted PowerShell version, runs
`sh scripts/run-phase-validation.sh`, and uploads ignored `out/jenkins/**`
fixtures as short-retention workflow artifacts for diagnosis. The workflow
does not require Jenkins credentials, registry access, a live controller, or a
cluster.

## Template Maintenance Evidence

The current machine-managed phase is `template-maintenance`. The completed
boundary-hardening transition evidence is the controller-free wrapper:

```sh
sh scripts/run-phase-validation.sh
```

That passing result means the local harness has evidence for the focused `dev`
dashboard lane, the full public-safe preset matrix, and the boundary-hardening
documentation package tracked by `docs/instructions/phase-gates.json`:

- `dev` job planning renders one bundle selection with validation, delivery,
  and promotion jobs under the `platform/dev` folder.
- The service pipeline plan can render the public service catalog without a
  `services/` directory because the built-in services are public-image examples
  and do not declare Jenkinsfile-backed jobs.
- Job DSL export can create the seed fixture under `out/jenkins/` while keeping
  repository URL, branch spec, and credentials ID values parameterized.
- Service pipeline validation, the aggregate Job DSL harness, and the public
  preset test suite all pass without contacting a Jenkins controller; the
  aggregate and test lanes both include a full public preset matrix fixture.
- Jenkins runtime helpers for repository validation, delivery, promotion, and
  workstation checks exist and can produce or verify a public-safe contract
  bundle under `out/`.

Use this evidence as a boundary, not as live-controller approval. The wrapper
does not install Jenkins plugins, verify JCasC, create credentials, check agent
tool images, or run delivery/promotion against a cluster. Boundary-hardening
docs are the evidence package for template-maintenance; live
controller rollout remains a separate controller, plugin, agent, credential, and
target-environment concern. See [phase-handoff.md](phase-handoff.md) for the
completed transition evidence, and see
[pipeline-boundaries.md](pipeline-boundaries.md) for the ownership map across
Job DSL generation, Pipeline DSL execution, service catalog metadata, and
controller/JCasC rollout.

If an automation dashboard reports `jenkins validation failed` for this target,
rerun the wrapper from a clean checkout before changing phase or rollout
language. A passing wrapper run means the repository-local Jenkins gate is green
again for the current checkout; record the refreshed evidence in
[phase-handoff.md](phase-handoff.md) when the dashboard status or phase evidence
needs to explain why the failure is no longer current. If the wrapper still
fails, keep the dashboard status as the active blocker and troubleshoot the first
failing labeled command from the wrapper output. Make sure the checkout can
write ignored fixtures under `out/`; the controller-free gate intentionally
generates Job DSL fixtures there during validation.

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
- The dependency inventory can report manifest-free package posture, public
  service image tags, and controller image risk indicators from committed files.
- Job DSL export can produce folder and `pipelineJob` definitions.
- The phase gate exercises both the focused `dev` transition commands and the
  all-preset public Job DSL harness.
- The all-preset harness verifies that the generated full matrix keeps every
  preset selection tied to service catalog metadata and only projects service
  jobs for catalog entries that are explicitly Jenkinsfile-backed.
- Generated bundle jobs preserve the validation, delivery, manual approval, and
  promotion dependency order.
- Every public preset application is represented in the service pipeline
  catalog, and catalog-only public-image services stay documented without
  generating Jenkins service jobs.
- Generated SCM URL, branch spec, and credentials ID values remain placeholders
  or parameters until a Jenkins seed job receives explicit values.
- Explicit seed SCM URL, branch spec, and credentials ID values are emitted as
  escaped Groovy strings while generated jobs still call `credentials(scmCredentialsId)`
  and `branch(branchSpec)`.
- Generated Jenkins job roots must resolve to at least one safe folder segment;
  blank roots, parent traversal, and expression-like path segments fail before
  Job DSL is generated.
- Seed SCM URLs must be HTTPS/SSH absolute URIs or Git scp-like paths; local
  file URLs and relative repository paths fail before Job DSL generation.
- Applying generated Job DSL with `SEED_REMOVED_JOB_ACTION=DELETE` requires the
  separate `SEED_CONFIRM_REMOVED_JOB_DELETE` guard.
- Applying generated Job DSL requires concrete repository URL and branch inputs,
  not blank values or the public-safe placeholders.
- Seed-generated Job DSL artifacts are archived only when generated metadata stays
  public-safe; concrete SCM values, credentials IDs, or registry overrides skip
  archival to avoid retaining environment-specific metadata in Jenkins artifacts.
- Jenkins artifact archive paths are literal workspace-relative paths under
  `out/`, not caller-controlled absolute paths, parent traversal, or Ant globs.
- Non-dry-run delivery and promotion stay manually approved, and the public-safe
  helper scripts fail closed for live deployment, Helm repository refresh, and
  bootstrap status checks that require downstream controller or cluster
  implementation.
- Runtime entrypoint scripts and public-safe values defaults referenced by the
  checked-in Jenkinsfiles exist in the repository.
- Service catalog required-file paths are relative service-local paths, not
  absolute paths, parent traversal, or glob patterns.
- Service catalog entries remain public-safe and internally consistent.
- Jenkinsfile-backed catalog services selected by presets or fixtures are
  projected into generated service jobs with service-local Jenkinsfile paths,
  de-duplicated across multiple selections, and associated with every selection
  that uses them.
- `-SkipServiceJobs` suppresses generated service jobs even when selected
  services are Jenkinsfile-backed.
- Jenkinsfile-backed catalog entries fail validation when the service directory
  exists but `services/<name>/Jenkinsfile` is missing.

## What These Checks Do Not Prove

- A live Jenkins controller has the required Job DSL plugin or JCasC setup.
- Jenkins agents have `kubectl`, `helm`, registry access, or cluster access.
- The controller-free contract bundle contains live cluster manifests.
- Dry-run delivery or promotion proves registry, Helm, Kubernetes, credential,
  or cluster permissions.
- Non-dry-run delivery and promotion can run without manual approval.

Review [jenkins/JOB_BLUEPRINT.md](../jenkins/JOB_BLUEPRINT.md) before changing
the Job DSL, Pipeline DSL, JCasC, or preset responsibility boundaries.
Use [maintenance.md](maintenance.md) for the change-lane checklist that maps
presets, profiles, service catalog entries, Job DSL export, Jenkinsfiles, and
controller/JCasC scope to their validation commands. Use
[phase-handoff.md](phase-handoff.md) when the wrapper passes and the next action
is a phase decision. Use [pipeline-boundaries.md](pipeline-boundaries.md) when
the change moves behavior between those ownership areas.
