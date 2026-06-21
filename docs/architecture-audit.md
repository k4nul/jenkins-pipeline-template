# Architecture Audit

This audit records the current `template-maintenance` architecture boundary for
the Jenkins pipeline template. It is intended as the first place to check before
moving behavior between job planning, Job DSL export, Jenkinsfile runtime logic,
service catalog metadata, or future controller/JCasC scope.

## Executive Summary

The repository is a controller-free Jenkins template generator. Public-safe
catalog data in `config/` flows into PowerShell plan and export scripts in
`scripts/`, which generate Jenkins job topology and Job DSL fixtures under
ignored `out/` paths. Jenkinsfiles in `jenkins/` consume the generated contract
at runtime and keep production actions behind dry-run defaults, approval prompts,
and fail-closed helper behavior.

The architecture is healthy for template maintenance. The most important
boundary is that `scripts/export-jenkins-job-dsl.ps1` consumes the canonical plan
model from `scripts/show-jenkins-job-plan.ps1`; it should not re-resolve presets,
profiles, or service catalog selection rules. The main maintainability risk is
size concentration in the plan builder and assertion harness, not a currently
failing boundary.

## Repository Architecture Map

| Area | Primary files | Ownership |
| --- | --- | --- |
| Public template inputs | `config/environments/*.psd1`, `config/profiles/*.psd1`, `config/service-pipelines.psd1`, `config/helm-releases.psd1` | Public-safe preset, profile, service, image, and values metadata. |
| Plan model | `scripts/show-jenkins-job-plan.ps1`, `scripts/environment-preset.ps1`, `scripts/platform-catalog.ps1`, `scripts/jenkins-job-common.ps1` | Selection resolution, job path normalization, bundle job topology, service-job projection, and local command contracts. |
| Job DSL export | `scripts/export-jenkins-job-dsl.ps1`, `scripts/jenkins-job-dsl-common.ps1`, `jenkins/job-seed.Jenkinsfile` | Folder and `pipelineJob` generation from the plan model, SCM placeholders, branch specs, credentials ID parameters, and seed apply guards. |
| Pipeline runtime | `jenkins/repository-validation.Jenkinsfile`, `jenkins/bundle-delivery.Jenkinsfile`, `jenkins/bundle-promotion.Jenkinsfile` | Jenkins execution flow, artifact paths, dry-run defaults, manual approvals, and public-safe live-action guardrails. |
| Validation harness | `scripts/run-phase-validation.sh`, `scripts/validate-jenkins-job-dsl.ps1`, `tests/jenkins-job-dsl.public-presets.ps1`, `scripts/jenkins-validation-assertions.ps1`, `scripts/jenkins-validation-fixtures.ps1` | Controller-free regression checks for plan/export/runtime contracts and synthetic service-job fixtures. |
| Controller examples and docs | `k8s/jenkins-controller/`, `docs/`, `jenkins/JOB_BLUEPRINT.md` | Optional controller examples, reader-facing boundaries, and rollout guidance that must not be treated as proof of live-controller readiness. |

## Main Entry Points

- `sh scripts/run-phase-validation.sh` is the repository-owned phase and
  dashboard validation wrapper. It resolves PowerShell, labels each step, runs
  the focused `dev` lane, runs aggregate Job DSL validation, and runs the public
  preset test suite.
- `pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -Format json`
  produces the canonical job plan model. Omitting `-EnvironmentPreset` renders
  the full public preset matrix.
- `pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -OutputPath
  out/jenkins/public-preset-matrix-seed-job-dsl.groovy` consumes the plan model
  and writes Job DSL only under ignored `out/` paths.
- `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` is the aggregate
  controller-free harness for presets, generated DSL, SCM safety, service-job
  fixtures, Jenkinsfile runtime contracts, and public-safe values defaults.
- `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` validates the
  service catalog boundary, including the current valid state where no
  `services/` directory is required because public catalog entries are not
  Jenkinsfile-backed.

## Data Flow And Dependency Direction

The intended dependency direction is one-way:

1. Public-safe catalog data is read from `config/`.
2. `scripts/show-jenkins-job-plan.ps1` resolves that data into a plan model with
   normalized job roots, selections, bundle jobs, service jobs, local commands,
   and a Mermaid topology.
3. `scripts/export-jenkins-job-dsl.ps1` invokes the plan script with JSON output
   and renders folders plus `pipelineJob` definitions from that model.
4. Jenkinsfiles invoke repository-owned scripts through named parameters and
   preserve dry-run and approval behavior at runtime.
5. Validation scripts call plan/export/runtime entry points but are not runtime
   dependencies for generated Jenkins jobs.

Keep this direction intact. Moving preset or service selection into the exporter
would create a second policy surface and make the Job DSL fixture less reliable
as a regression gate.

## Boundary And Coupling Findings

- The plan/export boundary is explicit and validated: the exporter calls the plan
  script for JSON rather than reconstructing selections.
- Job root and service root normalization are shared through
  `scripts/jenkins-job-common.ps1`, which keeps path safety consistent between
  plan and export paths.
- Validation is intentionally coupled to generated topology. That is useful for
  template maintenance, but the assertion suite is large and should not grow into
  runtime policy.
- Jenkinsfile runtime guard logic is duplicated across the repository validation,
  delivery, promotion, and seed entry points. Treat that as a deliberate local
  wrapper pattern unless a future package can prove a shared helper keeps Jenkins
  runtime behavior and validation evidence equivalent.
- Controller/JCasC work remains a documentation and future-validation boundary.
  A passing local wrapper is evidence for public-safe template generation, not
  evidence that a live Jenkins controller has plugins, credentials, agents, or
  cluster access.
- The current public service catalog is catalog-only. Service jobs should appear
  only when a selected catalog entry explicitly declares `HasJenkinsfile = $true`
  and the matching service Jenkinsfile exists.

## Risky Modules

- `scripts/show-jenkins-job-plan.ps1` has high responsibility: preset fallback,
  direct selection behavior, path construction, bundle job topology, service-job
  projection, output formatting, and Mermaid rendering all live in one script.
- `scripts/jenkins-validation-assertions.ps1` is the largest shared test policy
  surface. It is valuable, but future growth should stay grouped by boundary so
  assertion failures identify the owner area quickly. Side-effecting negative
  fixtures should not obscure the pure plan and DSL assertions.
- `tests/jenkins-job-dsl.public-presets.ps1` is an extended regression suite with
  broad scenario coverage. Keep new scenarios focused on one boundary at a time.
- `jenkins/job-seed.Jenkinsfile` bridges Jenkins runtime parameters and local
  export behavior. Preserve parameterized SCM values and artifact archival guards
  before changing seed behavior.
- `jenkins/*.Jenkinsfile` entry points repeat argument assembly, path checks, and
  control-character guards. Consolidate that only as a Jenkinsfile-runtime
  package with explicit validation of all generated jobs.
- `k8s/jenkins-controller/jenkins.yaml` uses the public `jenkins/jenkins:lts`
  controller image reference. Treat production controller dependency decisions as
  a dependency-plan or controller/JCasC package, not a Job DSL change.

## Recommendations

| Rank | Recommendation | Impact | Confidence | Effort |
| --- | --- | --- | --- | --- |
| 1 | Keep `scripts/run-phase-validation.sh` as the canonical dashboard and phase validation command. | High | High | Low |
| 2 | When modifying `scripts/show-jenkins-job-plan.ps1`, extract only cohesive plan-model helpers that remain covered by the full public preset matrix and service-job fixtures. | Medium | High | Medium |
| 3 | Keep exporter changes limited to Groovy rendering, folder descriptions, SCM placeholder safety, and output behavior; do not add catalog resolution there. | High | High | Low |
| 4 | Separate side-effecting validation fixture scenarios from pure plan and DSL assertions before adding more negative fixture coverage. | Medium | High | Medium |
| 5 | Group future assertion growth by boundary in `scripts/jenkins-validation-assertions.ps1` before adding more unrelated checks to existing functions. | Medium | Medium | Medium |
| 6 | Consolidate repeated Jenkinsfile runtime guard idioms only when the package validates repository validation, delivery, promotion, and seed behavior together. | Medium | Medium | Medium |
| 7 | Add a separate controller/JCasC validation lane only when controller configuration files are introduced. | Medium | High | Medium |

## Suggested Larger Work Packages

### Plan-Model Helper Extraction

Scope: Extract selection assembly or Mermaid rendering from
`scripts/show-jenkins-job-plan.ps1` without changing generated JSON, markdown,
or text output.

Acceptance criteria:

- `dev`, `staging`, `prod`, custom selection, and multi-preset outputs remain
  stable except for intentional formatting changes.
- Service-job projection still de-duplicates shared Jenkinsfile-backed service
  jobs across selected presets.
- The exporter continues to consume plan JSON rather than reimplementing
  selection rules.

Validation:

```sh
sh scripts/run-phase-validation.sh
```

### Validation Fixture Boundary Split

Scope: Separate pure plan/export assertions from side-effecting negative fixture
scenarios while preserving the public harness entry points.

Acceptance criteria:

- Existing assertion names used by `scripts/validate-jenkins-job-dsl.ps1` and
  `tests/jenkins-job-dsl.public-presets.ps1` remain available or are migrated in
  one cohesive patch.
- Failures still identify plan, export, service catalog, runtime, or phase
  evidence boundaries.
- Fixture creation, deletion, and catalog mutation stay in fixture-oriented
  helpers so read-only assertion helpers remain easier to reason about.

Validation:

```sh
sh scripts/run-phase-validation.sh
```

### Jenkinsfile Runtime Guard Consolidation

Scope: Consolidate repeated Jenkinsfile runtime guard idioms only if the resulting
shape stays easy to validate from the controller-free harness.

Acceptance criteria:

- Repository validation, delivery, promotion, and seed entry points keep their
  current named parameter contracts.
- SCM URL, branch spec, credentials ID, archive path, and live-action guards stay
  fail-closed.
- Non-dry-run delivery and promotion still require manual approval.

Validation:

```sh
sh scripts/run-phase-validation.sh
```

### Controller/JCasC Future Lane

Scope: Add controller or JCasC files only after choosing a new phase or explicit
maintenance package.

Acceptance criteria:

- Public defaults remain free of real credentials, private SCM URLs, and
  hardcoded branch policies.
- Live-controller readiness checks are validated separately from Job DSL export.
- Documentation keeps the distinction between controller-free fixtures and live
  rollout evidence.

Validation:

```sh
sh scripts/run-phase-validation.sh
```

Plus the new controller/JCasC validation command introduced by that package.

## Changes Made And Validation

This audit is documentation-only. It does not change script behavior, generated
Job DSL, dependency files, service catalog data, Jenkinsfiles, or phase metadata.

Validation evidence for the current checkout:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper passed on 2026-06-22 with PowerShell 7.6.2 and covered dependency
inventory, the focused `dev` job plan, service pipeline plan, ignored Job DSL
export, service pipeline validation, aggregate Job DSL validation, and the public
preset test suite.

## Suggested Next Automated Task

Use `test-generation` or `refactor-candidates` only if the next run selects a
cohesive helper-extraction or assertion-grouping package. Otherwise keep using
maintenance-oriented tasks in `template-maintenance` and rerun
`sh scripts/run-phase-validation.sh` when a progress dashboard reports a stale
`jenkins validation failed` status.
