# Dependency And Toolchain Plan

This repository does not use a package-manager manifest or lockfile. The
dependency surface is catalog and runtime-contract driven:

- public service image tags in `config/service-pipelines.psd1`
- the public-safe Jenkins controller example in `k8s/jenkins-controller/`
- GitHub Actions workflow actions in `.github/workflows/`
- Jenkins Pipeline and Job DSL behavior in `jenkins/` and `scripts/`
- PowerShell 7+ as the local validation runtime
- Jenkins agent tools used by cluster-aware repository validation and
  non-dry-run delivery and promotion paths

Use the repository-local inventory command before planning a dependency batch:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
```

The safe dependency posture is therefore "plan and validate before version
changes." Do not refresh image tags, controller images, Jenkins plugin
assumptions, or agent tool baselines from repository-local evidence alone.
First collect upstream release notes externally, choose one coherent batch, then
update the owning files and run the validation lane for that batch.

## Executive Summary

No dependency versions are changed by this plan. The current repository-local
health signal is that dependencies are explicit where the public template owns
them, generated dependency artifacts stay under ignored `out/` paths, and the
controller-free validation lane can prove Job DSL and service catalog shape
without contacting a Jenkins controller.

The main maintenance risk is provenance, not a directly proven vulnerability:
public image freshness, Jenkins LTS image drift, live controller plugins,
Jenkins agent images, and cluster tooling cannot be verified from committed
files alone. `scripts/show-dependency-inventory.ps1` now gives dependency runs a
controller-free inventory of the current catalog, controller image references,
checked-in CI workflow action refs, and checked-in Jenkins agent tool contracts,
but treat each upgrade candidate as requiring external release-note review plus
the local validation commands below.

## Current Validation Snapshot

On 2026-06-21, the repository-local dependency and Jenkins validation lane
passed with PowerShell 7.6.2. This run expanded the dependency inventory to
report checked-in Jenkins agent tool contracts. No dependency version was
changed because the committed evidence supports planning and controller-free
validation, not a safe release-note-reviewed image refresh.

Validated commands:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
```

The aggregate wrapper also passed:

```sh
sh scripts/run-phase-validation.sh
```

Inventory evidence from the same run:

- package manager manifests: `0`
- public service images: `4`
- controller image references: `1`
- floating controller image references: `jenkins/jenkins:lts`
- CI action references: `2`
- Jenkins agent tool contracts: `4`
- dependency risk posture: manifest-free repository, tag-based public service
  images, a floating public-safe Jenkins controller example image,
  version-tagged CI actions, and Jenkinsfile-declared agent tool requirements
  for non-dry-run rollout planning

## Dependency Inventory

| Area | Owning files | Repository-local dependency data | Validation lane |
| --- | --- | --- | --- |
| PowerShell runtime | `scripts/*.ps1`, `scripts/run-phase-validation.sh` | PowerShell 7 or newer through `pwsh`, `POWERSHELL_BIN`, `PWSH`, or common install paths | `sh scripts/run-phase-validation.sh` |
| Public service images | `config/service-pipelines.psd1` | `adminer:5.3.0-standalone`, `mccutchen/go-httpbin:v2.15.0`, `nginx:1.28-alpine`, `traefik/whoami:v1.10.4` | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json`; `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` |
| Dependency inventory | `scripts/show-dependency-inventory.ps1`, `config/service-pipelines.psd1`, `.github/workflows/*.yml`, `k8s/**/*.yaml`, `jenkins/*.Jenkinsfile` | package-manager manifest absence, public service image tags, controller image references, CI action references, Jenkins agent tool contracts, PowerShell validation contract | `pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json` |
| CI workflow actions | `.github/workflows/phase-validation.yml` | `actions/checkout@v4`, `actions/upload-artifact@v4` | `sh scripts/run-phase-validation.sh` |
| Environment presets and profiles | `config/environments/*.psd1`, `config/profiles/*.psd1` | Preset/profile selections, values-file paths, version defaults, selected applications/data services | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json` |
| Generated Job DSL | `scripts/export-jenkins-job-dsl.ps1`, `jenkins/job-seed.Jenkinsfile` | Job folder and `pipelineJob` generation, parameterized SCM URL, branch spec, and credentials ID handling | `pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy`; `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json` |
| Jenkins controller example | `k8s/jenkins-controller/jenkins.yaml`, `k8s/jenkins-controller/README.md` | `jenkins/jenkins:lts` and ephemeral `emptyDir` storage for a public-safe example only | Manifest review plus future controller/JCasC validation when those files exist |
| Jenkins Pipeline runtime | `jenkins/*.Jenkinsfile` | Runtime calls into repository-owned scripts, artifact paths under `out/`, dry-run defaults, manual approval gates | `sh scripts/run-phase-validation.sh`, plus live Jenkins review before rollout |
| Jenkins agent tools | `jenkins/*.Jenkinsfile`, `scripts/validate-workstation.ps1`, docs under `docs/` | `kubectl` and `helm` for strict cluster workflows; `git`, `docker`, and `python` as optional or context-dependent checks | Local workstation validation, then live agent readiness review before non-dry-run use |

There are no committed `package.json`, lockfile, `requirements*.txt`,
`pyproject.toml`, `go.mod`, `Cargo.toml`, `.csproj`, or similar language package
manifests in this repository.

## Toolchain And Runtime Constraints

- Keep PowerShell compatibility at PowerShell 7+ unless a repository-local
  validation change proves a newer minimum is required.
- Keep repository URLs, branch specs, credentials IDs, Docker registry values,
  and production deploy/dry-run controls parameterized in generated jobs and
  checked-in Jenkinsfiles. Preserve manual approval prompts for non-dry-run
  delivery and promotion.
- Keep public sample image tags in `config/service-pipelines.psd1`; do not
  duplicate image ownership in generated Job DSL, Jenkinsfiles, or controller
  examples.
- Keep generated dependency and Job DSL artifacts under `out/`. The directory is
  ignored and must not become the source of committed controller state.
- Treat the Kubernetes controller manifest as a public-safe example, not as a
  production dependency baseline. Plugin installation, controller credentials,
  security realm, durable storage, and agent image selection belong to a future
  controller/JCasC package.

## Staged Upgrade Plan

### Stage 1: Public Image Catalog Refresh

Update only `config/service-pipelines.psd1` after choosing new public image tags
from upstream release notes. Keep the current catalog-only behavior unless the
same change adds a matching `services/<name>/Jenkinsfile`, required files, and
validation expectations.

Files likely to change together:

- `config/service-pipelines.psd1`
- `docs/dependency-plan.md`
- `docs/maintenance.md` or `docs/testing.md` if validation guidance changes

Validation:

```powershell
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
```

### Stage 2: Controller Image And Plugin Baseline

Keep `k8s/jenkins-controller/jenkins.yaml` as an example until a controller or
JCasC package owns plugin and agent decisions. If the floating
`jenkins/jenkins:lts` image is replaced with a pinned image, update
`k8s/jenkins-controller/README.md` in the same change so image pinning, durable
storage expectations, plugin ownership, and validation limits remain explicit.

Files likely to change together:

- `k8s/jenkins-controller/jenkins.yaml`
- `k8s/jenkins-controller/README.md`
- future JCasC or controller validation files, when introduced

Validation:

```powershell
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
```

Add live-controller or JCasC validation only when the controller/JCasC files
exist.

### Stage 3: PowerShell And Jenkins Agent Tool Baseline

Keep PowerShell 7+ as the minimum local runtime. If Jenkins agent images are
standardized later, update the Jenkinsfile preflight expectations and reader
documentation together so `kubectl`, `helm`, registry, Docker, and cluster
assumptions stay visible.

Files likely to change together:

- `scripts/run-phase-validation.sh`
- `scripts/validate-workstation.ps1`
- `jenkins/*.Jenkinsfile`
- `docs/testing.md`
- `docs/maintenance.md`

Validation:

```sh
sh scripts/run-phase-validation.sh
```

### Stage 4: CI Workflow Action Refresh

Update only `.github/workflows/phase-validation.yml` after reviewing release
notes for the checked-in GitHub Actions. Keep the workflow controller-free and
continue uploading only ignored `out/jenkins/**` diagnostic artifacts.

Files likely to change together:

- `.github/workflows/phase-validation.yml`
- `docs/dependency-plan.md`
- `docs/testing.md` if workflow behavior or artifact handling changes

Validation:

```sh
sh scripts/run-phase-validation.sh
```

### Stage 5: Jenkinsfile Behavior Dependencies

Add Jenkins Pipeline unit tests or an equivalent local test harness only when
scripted Jenkinsfile logic grows beyond the current declarative wrappers and
repository-owned PowerShell entrypoints. Keep non-dry-run delivery and promotion
behind explicit approval and public-safe helper guardrails; live deployment,
Helm repository refresh, and bootstrap status checks belong to downstream
controller or cluster rollout work.

Files likely to change together:

- `jenkins/*.Jenkinsfile`
- `jenkins/JOB_BLUEPRINT.md`
- `docs/testing.md`
- future Jenkinsfile test fixtures

Validation:

```sh
sh scripts/run-phase-validation.sh
```

## Likely Breaking Changes To Investigate

- Public image tag updates can change exposed ports, startup timing, default
  users, filesystem paths, health endpoints, and environment variables.
- Moving from floating Jenkins LTS to a pinned controller image can reveal plugin
  and Java runtime compatibility gaps that local Job DSL export does not prove.
- Introducing a JCasC plugin baseline can move responsibility from documentation
  into controller validation; keep that separate from public service image
  refreshes.
- Raising the PowerShell minimum can break older Jenkins agents even when local
  validation passes on a newer workstation.
- Adding Jenkinsfile-backed services changes `ServiceJobCount` and must update
  service fixtures, required-file checks, generated Job DSL expectations, and
  documentation in the same stage.
- Standardizing Jenkins agent images can make optional tools mandatory. Keep
  strict/non-strict workstation validation behavior explicit before rollout.

## Test Areas To Run After Each Stage

| Change package | Minimum validation | Extra review before rollout |
| --- | --- | --- |
| Public service image tag refresh | `show-service-pipeline-plan.ps1`; `validate-service-pipelines.ps1`; `validate-jenkins-job-dsl.ps1 -Format json` | Image release notes, health endpoints, exposed ports, compose examples |
| Controller image or future JCasC baseline | `validate-jenkins-job-dsl.ps1 -Format json` until controller files exist | Live controller plugin install, JCasC load, durable storage, credentials providers, security realm |
| PowerShell runtime or validation wrapper | `sh scripts/run-phase-validation.sh` | Jenkins agent PowerShell version, shell path resolution, non-interactive execution |
| Jenkins agent tool baseline | `sh scripts/run-phase-validation.sh` plus `validate-workstation.ps1` in the target agent context | `kubectl`, `helm`, registry access, Docker availability, cluster permissions |
| CI workflow action refresh | `sh scripts/run-phase-validation.sh` | Action release notes, artifact retention behavior, workflow permissions |
| Jenkinsfile behavior dependency | `sh scripts/run-phase-validation.sh` | Live Jenkins dry-run, approval prompts, artifact archiving under `out/`, and downstream live-action implementation review |

## Security Or Maintenance Risk Indicators

- `k8s/jenkins-controller/jenkins.yaml` uses floating `jenkins/jenkins:lts`.
  That is acceptable for a public-safe example but should be reviewed before
  production use.
- There is no Jenkins plugin lockfile or generated dependency snapshot, because
  controller plugins are outside the current template scope.
- Public image freshness cannot be determined from repository-local files alone.
  Check image release notes externally before changing tags.
- Controller-free validation proves generated Job DSL shape and public-safe
  defaults; it does not prove live Jenkins plugin installation, credential
  providers, agent image contents, registry access, or cluster permissions.
- Jenkins agent tool requirements are declared in checked-in Jenkinsfiles and
  now appear in the dependency inventory; use that evidence before changing
  agent images or making optional tools mandatory.
- GitHub Actions workflow dependencies are version-tag based. Review action
  release notes before changing those refs, and keep workflow permissions at
  `contents: read` unless a separate task proves broader access is required.
- Generated artifacts under `out/` are intentionally ignored. A change that
  commits generated Job DSL or controller output would blur the source of truth.
- The repository has no language package lockfile to audit because it has no
  language package manifest; vulnerability status would require external checks
  and must not be inferred from this file alone.

## Suggested Larger Upgrade Or Hygiene Packages

1. Public image catalog refresh package

   Review upstream release notes for the four public service images, update
   `config/service-pipelines.psd1` as one catalog batch, and record any changed
   runtime assumptions in service catalog documentation.

2. Controller/JCasC baseline package

   Decide whether the public example should remain floating or become pinned.
   If pinned, add documentation for plugin ownership, durable storage, agent
   image expectations, and live-controller validation.

3. Agent tool baseline package

   Define the Jenkins agent image/tool contract for non-dry-run delivery and
   promotion, then align `validate-workstation.ps1`, Jenkinsfile preflights, and
   testing docs.

4. CI workflow action refresh package

   Review `actions/checkout` and `actions/upload-artifact` release notes,
   update `.github/workflows/phase-validation.yml` as one workflow batch, and
   confirm the controller-free wrapper still passes locally before relying on
   hosted workflow evidence.

5. Jenkinsfile unit strategy package

   If conditional Pipeline DSL grows, add a focused unit-test strategy for
   Jenkinsfile behavior instead of expanding controller-free PowerShell checks
   beyond their ownership boundary.

## Changes Made And Validation

This run updated the dependency inventory to report checked-in CI workflow
action references alongside Jenkins agent tool contracts and refreshed the
dependency-plan hygiene record. It makes no dependency version changes and does
not add runtime dependencies.

Validation completed:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
```

```sh
sh scripts/run-phase-validation.sh
git diff --check
```

For future dependency planning changes, start with:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
```

When this file is updated alongside dependency, catalog, Jenkinsfile, Job DSL, or
phase-readiness behavior, also run:

```sh
sh scripts/run-phase-validation.sh
```

## Suggested Next Automated Task

Continue `template-maintenance` dependency work only when a change preserves the
Job DSL, Pipeline DSL, service catalog, and controller/JCasC responsibility
boundaries. The current validation command is still the repository-owned
`sh scripts/run-phase-validation.sh` wrapper for changes that affect dependency
inventory evidence or phase-readiness wording.
