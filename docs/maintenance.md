# Jenkins Maintenance Runbook

Use this runbook when changing Jenkins job planning, Job DSL export, service
pipeline metadata, or the documentation that explains those areas. It keeps the
public template safe to inspect without a live Jenkins controller.

For a focused ownership map across generated Job DSL, checked-in Jenkinsfiles,
service catalog metadata, and live controller/JCasC rollout, read
[pipeline-boundaries.md](pipeline-boundaries.md) with this runbook. For the
current architecture audit, risk map, and ranked maintenance work packages, read
[architecture-audit.md](architecture-audit.md).

## Maintenance Rules

- Keep repository URLs, branch specs, and Jenkins credentials IDs parameterized.
- Do not hardcode company-specific SCM URLs, credentials IDs, controller names,
  branch policies, or production environment values.
- Keep generated Job DSL and validation fixtures under `out/`; do not commit
  generated controller output.
- Keep non-dry-run delivery and promotion behind the existing manual Jenkins
  approval prompts and public-safe helper guardrails. Live deployment, Helm
  repository refresh, and bootstrap status checks require downstream controller
  or cluster implementation outside this reusable template.
- Treat live Jenkins controller plugin installation, agents, credentials, and
  security realm configuration as JCasC/controller concerns, not default Job DSL
  or Pipeline DSL behavior in this reusable template.

## Responsibility Map

| Area | Primary files | What belongs there | Validation |
| --- | --- | --- | --- |
| Environment presets | `config/environments/*.psd1` | Preset names, profile choices, application/data-service selections, values paths, version/output defaults | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Profiles | `config/profiles/*.psd1` | Reusable bundle shapes consumed by presets and direct selections | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Service pipeline catalog | `config/service-pipelines.psd1` | Public image service metadata and whether a service has its own Jenkinsfile-backed job | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json` and `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` |
| Job plan | `scripts/show-jenkins-job-plan.ps1` | Folder paths, generated bundle job plans, service job plans, and local command contracts | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json` for preview; `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -Format json` for the full preset matrix |
| Job DSL export | `scripts/export-jenkins-job-dsl.ps1`, `jenkins/job-seed.Jenkinsfile` | Jenkins folders, `pipelineJob` definitions, SCM placeholders, branch specs, credentials parameters, lightweight checkout, and seed apply guards | `pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -OutputPath out/jenkins/public-preset-matrix-seed-job-dsl.groovy` |
| Pipeline runtime | `jenkins/*.Jenkinsfile` | Validation, delivery, promotion, archive, dry-run defaults, approval prompts, and public-safe live-action guards | `sh scripts/run-phase-validation.sh`, plus live Jenkins review before rollout |
| Controller/JCasC scope | `k8s/jenkins-controller/README.md`, future JCasC files | Example controller deployment, plugin baseline, agents, credentials providers, and controller security | Controller or JCasC validation when those files exist |

## Change Lanes

### Presets Or Profiles

Update the preset or profile files together with any reader-facing description
in `config/environments/README.md`, `config/profiles/README.md`, `README.md`, or
`jenkins/JOB_BLUEPRINT.md`.

Validate with the full public preset matrix:

```powershell
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

### Job Plan Or Job DSL Export

Preview the `dev` plan when you need a small readable example, export the full
public preset matrix fixture, then run the aggregate harness:

```powershell
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -OutputPath out/jenkins/public-preset-matrix-seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

Before applying generated DSL in Jenkins, set `SEED_REPO_URL` and
`SEED_BRANCH_SPEC` as seed parameters, and set `SEED_SCM_CREDENTIALS_ID` only
when the selected repository needs Jenkins-managed credentials. Keep the
generated jobs calling `credentials(scmCredentialsId)` and `branch(branchSpec)`
instead of inlining real values. `SEED_REPO_URL` must be an HTTPS/SSH
repository URI or a Git scp-like path; local file URLs and relative paths are
rejected before DSL generation.

### Service Pipeline Catalog

The current catalog is public-image only, and every service has
`HasJenkinsfile = $false`. A missing `services/` directory is valid only while
the catalog has no Jenkinsfile-backed services. If a service is marked
Jenkinsfile-backed, validation requires `services/<name>/Jenkinsfile` even when
the service directory and other required files exist.

When adding a Jenkinsfile-backed service:

1. Set `HasJenkinsfile = $true` for that service.
2. Add `services/<name>/Jenkinsfile` and the required files declared by the
   catalog entry.
3. Add any required Jenkinsfile text assertions to the catalog.
4. Validate the service plan, service validator, and full Job DSL harness.

```powershell
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

### Jenkinsfiles

Keep repository validation, delivery, and promotion responsibilities separate.
Preserve dry-run defaults, explicit approval for non-dry-run deployment, and
fail-closed behavior for live deployment, Helm repository refresh, and bootstrap
status checks until a downstream controller or cluster rollout implements those
actions.

Run the phase wrapper after changing Jenkinsfiles or generated job topology:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper labels each command and reports the first failing label, exit code,
and command. The GitHub Actions `Jenkins Phase Validation` workflow runs this
same wrapper and uploads ignored `out/jenkins/**` fixtures as short-retention
diagnostic artifacts. Keep those fixtures out of Git; they are evidence for the
controller-free run, not generated controller output to publish.

This controller-free check does not prove the Job DSL plugin, Jenkins agents,
credentials providers, registry access, or cluster permissions exist on a live
controller. Verify those separately during rollout.

### Dependencies Or Tooling

Use `docs/dependency-plan.md` before changing public image tags, Jenkins
controller images, plugin assumptions, Jenkins agent tool baselines, or the
PowerShell runtime expectation.

Start with the controller-free inventory so the change package is based on
committed catalog and manifest evidence:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
```

## Phase Handoff

The current machine-managed phase is `template-maintenance`. The previous
`job-dsl-coverage` and boundary-hardening transition gate remains the
public-safe validation wrapper for generated Job DSL, service pipeline catalog,
and runtime contract changes:

```sh
sh scripts/run-phase-validation.sh
```

That wrapper proves the focused `dev` job plan, service plan, Job DSL export,
service pipeline validation, individual public preset fixtures, a combined full
public preset matrix fixture, the public preset test suite, committed runtime
contract, and dependency inventory evidence from the public service catalog and
controller manifests.

The completed `pipeline-boundary-hardening` phase keeps the Job DSL, Pipeline
DSL, service catalog, and future JCasC responsibilities explicit. Keep
[phase-handoff.md](phase-handoff.md) as the audit trail for the passing local
gate and for the live-controller checks that remain separate from public
defaults. Use [validation-evidence.md](validation-evidence.md) when the work is
only to refresh or explain a stale `jenkins validation failed` dashboard signal
without selecting a new phase.

The reader-facing boundary package is
[pipeline-boundaries.md](pipeline-boundaries.md). Keep it aligned with
`jenkins/JOB_BLUEPRINT.md`, `jenkins/README.md`, and the validation commands in
this runbook when future changes move responsibilities between template
generation, Jenkinsfile execution, service catalog metadata, and controller
rollout.

The required transition gates are recorded in
`docs/instructions/phase-gates.json`: the wrapper machine-check passed, and the
boundary documentation, pipeline unit strategy, public preset matrix, and
handoff evidence gates remain recorded as passed. The manifest has no pending
`next_phase`; select one with a transition validation command before routing
another phase-transition.

In `template-maintenance`, use the same responsibility map to pick the narrowest
safe validation command. Maintenance work may update docs, security notes, audit
findings, dependency plans, or public-safe template behavior, but new Jenkins
platform scope should first get an explicit phase or owner decision instead of
silently expanding the reusable template.

When a maintenance run refreshes validation evidence, prefer this order:

1. Run `sh scripts/run-phase-validation.sh`.
2. If it passes, update only the handoff or report text that needs current
   evidence.
3. If it fails, keep the first failing wrapper label as the maintenance blocker.
4. Leave `docs/instructions/phase-gates.json` unchanged unless the selected task
   is a phase-transition with a new `next_phase` and transition command.

## Pipeline Boundary Hardening Checklist

Use this checklist when preparing documentation or implementation work for the
`template-maintenance` handoff. It keeps responsibility boundaries explicit
without adding controller-dependent requirements to the public defaults.

| Boundary | Keep in this repository | Keep outside the public default |
| --- | --- | --- |
| Job DSL | Folder paths, `pipelineJob` declarations, SCM parameter names, branch spec parameters, credentials ID parameters, lightweight checkout settings, and removed-job apply guards | Real SCM URLs, real credentials IDs, controller names, private folder policies, and organization-specific branch protections |
| Pipeline DSL | Validation, delivery, promotion, archive, dry-run defaults, manual approval prompts, and public-safe live-action guards in checked-in Jenkinsfiles | Unapproved production deployment behavior, private cluster assumptions, and controller-specific credential lookup logic |
| JCasC/controller | Public-safe examples and documentation for plugin, agent, credential-provider, and security-realm expectations | Treating a live controller plugin set as proven by local Job DSL export, or embedding private controller configuration in generated jobs |
| Service catalog | Public image metadata, required service-local file expectations, and whether a selected service has a Jenkinsfile-backed job | Generated service jobs for catalog entries that do not provide `services/<name>/Jenkinsfile` and matching required files |

Before moving a concern across a boundary, run the command lane for the source
area in the responsibility map above and update the matching reader-facing
document. For example, a new Jenkinsfile-backed service needs service catalog
docs, service validation, and the aggregate Job DSL harness; a future JCasC
package needs separate controller validation guidance instead of broadening the
controller-free phase gate.
