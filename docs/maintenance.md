# Jenkins Maintenance Runbook

Use this runbook when changing Jenkins job planning, Job DSL export, service
pipeline metadata, or the documentation that explains those areas. It keeps the
public template safe to inspect without a live Jenkins controller.

## Maintenance Rules

- Keep repository URLs, branch specs, and Jenkins credentials IDs parameterized.
- Do not hardcode company-specific SCM URLs, credentials IDs, controller names,
  branch policies, or production environment values.
- Keep generated Job DSL and validation fixtures under `out/`; do not commit
  generated controller output.
- Keep non-dry-run delivery and promotion behind the existing manual Jenkins
  approval prompts and bootstrap readiness checks.
- Treat live Jenkins controller plugin installation, agents, credentials, and
  security realm configuration as JCasC/controller concerns, not default Job DSL
  or Pipeline DSL behavior in this reusable template.

## Responsibility Map

| Area | Primary files | What belongs there | Validation |
| --- | --- | --- | --- |
| Environment presets | `config/environments/*.psd1` | Preset names, profile choices, application/data-service selections, values paths, version/output defaults | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Profiles | `config/profiles/*.psd1` | Reusable bundle shapes consumed by presets and direct selections | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Service pipeline catalog | `config/service-pipelines.psd1` | Public image service metadata and whether a service has its own Jenkinsfile-backed job | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json` and `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` |
| Job plan | `scripts/show-jenkins-job-plan.ps1` | Folder paths, generated bundle job plans, service job plans, and local command contracts | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json` |
| Job DSL export | `scripts/export-jenkins-job-dsl.ps1`, `jenkins/job-seed.Jenkinsfile` | Jenkins folders, `pipelineJob` definitions, SCM placeholders, branch specs, credentials parameters, lightweight checkout, and seed apply guards | `pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy` |
| Pipeline runtime | `jenkins/*.Jenkinsfile` | Validation, delivery, promotion, archive, dry-run, approval, and bootstrap readiness flow | `sh scripts/run-phase-validation.sh`, plus live Jenkins review before rollout |
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

Preview the plan, export the `dev` DSL fixture, then run the aggregate harness:

```powershell
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
```

Before applying generated DSL in Jenkins, set `SEED_REPO_URL`,
`SEED_BRANCH_SPEC`, and `SEED_SCM_CREDENTIALS_ID` as seed parameters. Keep the
generated jobs calling `credentials(scmCredentialsId)` and `branch(branchSpec)`
instead of inlining real values.

### Service Pipeline Catalog

The current catalog is public-image only, and every service has
`HasJenkinsfile = $false`. A missing `services/` directory is valid only while
the catalog has no Jenkinsfile-backed services.

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
bootstrap readiness checks before production-facing actions.

Run the phase wrapper after changing Jenkinsfiles or generated job topology:

```sh
sh scripts/run-phase-validation.sh
```

This controller-free check does not prove the Job DSL plugin, Jenkins agents,
credentials providers, registry access, or cluster permissions exist on a live
controller. Verify those separately during rollout.

### Dependencies Or Tooling

Use `docs/dependency-plan.md` before changing public image tags, Jenkins
controller images, plugin assumptions, Jenkins agent tool baselines, or the
PowerShell runtime expectation.

## Phase Handoff

The current machine-managed phase is `job-dsl-coverage`. Its transition gate is:

```sh
sh scripts/run-phase-validation.sh
```

That wrapper proves the focused `dev` job plan, service plan, Job DSL export,
service pipeline validation, and the full public preset matrix harness.

The next phase, `pipeline-boundary-hardening`, is for keeping the Job DSL,
Pipeline DSL, and future JCasC responsibilities explicit. Documentation updates
may improve those explanations, but only a `phase-transition` task should edit
`docs/instructions/phase-gates.json` or other phase metadata.

## Pipeline Boundary Hardening Checklist

Use this checklist when preparing documentation or implementation work for the
next phase. It keeps responsibility boundaries explicit without adding
controller-dependent requirements to the public defaults.

| Boundary | Keep in this repository | Keep outside the public default |
| --- | --- | --- |
| Job DSL | Folder paths, `pipelineJob` declarations, SCM parameter names, branch spec parameters, credentials ID parameters, lightweight checkout settings, and removed-job apply guards | Real SCM URLs, real credentials IDs, controller names, private folder policies, and organization-specific branch protections |
| Pipeline DSL | Validation, delivery, promotion, archive, dry-run defaults, manual approval prompts, and bootstrap readiness checks in checked-in Jenkinsfiles | Unapproved production deployment behavior, private cluster assumptions, and controller-specific credential lookup logic |
| JCasC/controller | Public-safe examples and documentation for plugin, agent, credential-provider, and security-realm expectations | Treating a live controller plugin set as proven by local Job DSL export, or embedding private controller configuration in generated jobs |
| Service catalog | Public image metadata, required service-local file expectations, and whether a selected service has a Jenkinsfile-backed job | Generated service jobs for catalog entries that do not provide `services/<name>/Jenkinsfile` and matching required files |

Before moving a concern across a boundary, run the command lane for the source
area in the responsibility map above and update the matching reader-facing
document. For example, a new Jenkinsfile-backed service needs service catalog
docs, service validation, and the aggregate Job DSL harness; a future JCasC
package needs separate controller validation guidance instead of broadening the
controller-free phase gate.
