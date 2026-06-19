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

## Script Ownership Boundaries

The controller-free validation lane depends on one direction of data flow:

1. `config/environments/*.psd1`, `config/profiles/*.psd1`, and
   `config/service-pipelines.psd1` define public-safe catalog data.
2. `scripts/show-jenkins-job-plan.ps1` resolves that catalog data into the
   canonical job plan model, including normalized bundle and service job roots.
3. `scripts/export-jenkins-job-dsl.ps1` consumes the job plan model and writes
   Job DSL; it should not reimplement preset, profile, service selection, or
   generated root normalization decisions that belong to the plan model.
4. `jenkins/*.Jenkinsfile` execute the checked-in validation, delivery,
   promotion, and seed entrypoints; they should keep runtime argument handling
   separate from plan-model decisions.
5. `scripts/jenkins-validation-assertions.ps1` and
   `tests/jenkins-job-dsl.public-presets.ps1` verify the public contract across
   the plan model, generated DSL, service catalog, and Jenkinsfile runtime
   guardrails.

Keep helper ownership narrow. Put helpers in `scripts/jenkins-job-common.ps1`
only when multiple entrypoints share the same rule, such as job path
normalization, repository output safety, service catalog loading, or generated
folder path derivation. Keep command-rendering helpers, Groovy formatting
helpers, and fixture-specific assertions close to the entrypoint that owns the
format. This avoids making the shared helper file a second policy layer.

## Refactor Guardrails

When reducing script size or duplication, preserve these dependency rules:

- the plan script may read presets, profiles, and service catalog metadata;
- the exporter should call the plan script and transform its JSON into Job DSL;
- validators may call plan and export entrypoints but should not become a
  required runtime dependency for Jenkins jobs;
- Jenkinsfiles should call repository-owned scripts through named parameters
  and keep deployment side effects behind existing dry-run, approval, and
  bootstrap readiness gates; and
- future Controller/JCasC files should get their own validation lane instead of
  broadening the local Job DSL export contract.

Continue extracting cohesive plan-model assembly functions from
`scripts/show-jenkins-job-plan.ps1` only when the existing public preset matrix
and service-job fixtures remain the acceptance tests. Keep service usage and
Jenkinsfile-backed service job projection inside the plan model, and avoid
moving behavior between Job DSL, Pipeline DSL, service catalog, and
Controller/JCasC boundaries in the same change.

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
When seed parameters include a concrete registry override, treat the generated
DSL as environment-specific metadata and skip Jenkins artifact archival just as
you would for concrete SCM values or credentials IDs.
Generated job roots must remain non-empty Jenkins folder paths made from safe
literal segments; blank roots, parent traversal, and expression-like segments
fail before Job DSL is generated.

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
- private values, downstream render/deploy behavior, and environment-specific
  runtime extensions are present outside the public defaults when needed;
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
