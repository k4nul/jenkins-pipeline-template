# Pipeline Boundary Guide

Use this guide when deciding whether a Jenkins template change belongs in Job
DSL generation, Pipeline DSL execution, service catalog metadata, or live
controller/JCasC rollout. The local validation lane is controller-free by
design, so these boundaries keep public template checks useful without implying
that a live Jenkins controller is ready.

## Boundary Summary

| Boundary | Repository-owned scope | Keep out of public defaults | First validation lane |
| --- | --- | --- | --- |
| Job DSL | Jenkins folders, `pipelineJob` entries, upstream relationships, SCM parameter names, branch specs, credentials ID parameters, lightweight checkout, and removed-job apply guards | Real SCM URLs, real credentials IDs, controller names, private folders, organization branch policies, and generated controller output | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Pipeline DSL | Repository validation, bundle delivery, bundle promotion, archive paths, dry-run defaults, manual approval prompts, and bootstrap readiness/status checks in `jenkins/*.Jenkinsfile` | Unapproved production deployment behavior, private cluster assumptions, and controller-specific credential lookup logic | `sh scripts/run-phase-validation.sh` plus live rollout review |
| Service catalog | Public image service metadata, required service-local file expectations, and whether selected services have Jenkinsfile-backed jobs | Service jobs for catalog entries that do not provide `services/<name>/Jenkinsfile` and matching required files | `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` |
| Controller/JCasC | Public-safe examples and documentation for plugin, agent, credential-provider, and security-realm expectations | Treating local Job DSL export as proof that a live controller has plugins, agents, credentials, registry access, or cluster access | Separate controller or JCasC validation when those files exist |

## Job DSL Boundary

Job DSL generation belongs in `scripts/show-jenkins-job-plan.ps1`,
`scripts/export-jenkins-job-dsl.ps1`, and `jenkins/job-seed.Jenkinsfile`.
Generated jobs may consume SCM values, but the reusable template must keep
repository URL, branch spec, and credentials ID parameterized.

Before applying generated DSL in Jenkins, provide seed parameters from the
controller or seed job:

- `SEED_REPO_URL`
- `SEED_BRANCH_SPEC`
- `SEED_SCM_CREDENTIALS_ID` when credentials are required
- optional folder roots such as `SEED_JOB_ROOT` and `SEED_SERVICE_JOB_ROOT`

Do not commit real values for those parameters and do not commit generated DSL
from a real controller. Local fixtures belong under ignored `out/` paths.

## Pipeline DSL Boundary

Pipeline DSL execution belongs in the Jenkinsfiles under `jenkins/`. Keep the
validation, delivery, and promotion jobs separate, and preserve these safety
rules:

- delivery and promotion default to dry-run style behavior until explicitly
  enabled;
- non-dry-run delivery and promotion require manual Jenkins approval prompts;
- bootstrap secret readiness and bootstrap status checks run before
  production-facing actions;
- archive paths remain workspace-relative paths under `out/`.

The local harness checks generated job topology and safety expectations. It does
not execute a live delivery or promotion against a cluster.

## Service Catalog Boundary

Service pipeline metadata belongs in `config/service-pipelines.psd1`. The
current public examples use public images and set `HasJenkinsfile = $false`, so
service-specific Jenkins jobs are not expected and `ServiceJobCount` can remain
`0`.

When adding a Jenkinsfile-backed service, update the catalog and service files
together:

1. Set `HasJenkinsfile = $true` for the service.
2. Add `services/<name>/Jenkinsfile`.
3. Add required service-local files declared by the catalog entry.
4. Add any required Jenkinsfile text assertions.
5. Run the service validation and aggregate Job DSL harness.

If a catalog entry declares Jenkinsfile-backed behavior but the matching
`services/<name>/Jenkinsfile` is missing, validation should fail closed.

## Controller And JCasC Boundary

Live Jenkins controller setup is outside the controller-free phase gate unless
the repository adds an explicit public-safe controller or JCasC package. Verify
these concerns separately before rollout:

- Job DSL plugin and any other controller plugins are installed or declared;
- Jenkins agents provide `pwsh`, `git`, `kubectl`, and `helm` as required by
  the selected Jenkinsfiles;
- credentials providers and credential IDs exist on the controller;
- runtime helper scripts and environment value files referenced by the
  Jenkinsfiles exist in the target repository or seeded workspace;
- registry and cluster permissions are available for non-dry-run delivery and
  promotion.

A passing local phase gate is evidence for public-safe template generation, not
for live-controller readiness.

## Validation Decision Tree

Use the narrowest command that covers the changed boundary, then run the wrapper
when the change affects phase readiness or generated job topology.

| Change | Minimum command | Broader command |
| --- | --- | --- |
| Single preset data | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -EnvironmentPreset <name>` | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Shared profile data | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` | `sh scripts/run-phase-validation.sh` when the profile changes generated topology or phase-readiness evidence |
| Service catalog metadata | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json` and `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Job plan or Job DSL export | `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json` and `pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy` | `sh scripts/run-phase-validation.sh` |
| Jenkinsfile flow or generated topology | `sh scripts/run-phase-validation.sh` | Live Jenkins rollout checks before enabling non-dry-run jobs |
| Controller/JCasC package | Controller or JCasC validation for that package | Local template harness plus live-controller verification |

For documentation-only changes that restate existing commands and boundaries,
use Markdown review and `git diff --check`. Rerun `sh
scripts/run-phase-validation.sh` when documentation changes describe command
behavior, generated job topology, or phase readiness.
