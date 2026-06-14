# Dependency And Toolchain Plan

This repository does not use a package-manager manifest or lockfile. The
dependency surface is the Jenkins controller example, public sample service
images, Jenkins agent tools, and the PowerShell validation runtime.

The current safe dependency posture is therefore "plan and validate before
version changes." Do not refresh image tags, Jenkins plugin assumptions, or
agent tool baselines from this repository alone. First collect upstream release
notes externally, choose a coherent batch, then update the source file and run
the validation lane listed below.

## Inventory

| Area | Files | Current constraint | Validation lane |
| --- | --- | --- | --- |
| PowerShell runtime | `scripts/*.ps1`, `scripts/run-phase-validation.sh` | PowerShell 7 or newer through `pwsh`, `POWERSHELL_BIN`, or `PWSH` | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Jenkins controller example | `k8s/jenkins-controller/jenkins.yaml` | `jenkins/jenkins:lts` example image | Review manifest plus controller/JCasC validation when a JCasC package exists |
| Public sample services | `config/service-pipelines.psd1` | `adminer:5.3.0-standalone`, `mccutchen/go-httpbin:v2.15.0`, `nginx:1.28-alpine`, `traefik/whoami:v1.10.4` | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json` and `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1` |
| Generated Job DSL | `scripts/export-jenkins-job-dsl.ps1`, `jenkins/job-seed.Jenkinsfile` | Job DSL plugin availability is a live-controller concern, not committed here | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Jenkins agent tools | `jenkins/*.Jenkinsfile`, `jenkins/README.md` | `kubectl` and `helm` are required for non-dry-run cluster workflows; `git`, `docker`, and `python` are optional preflight checks | Jenkins agent readiness preflight plus controller-free harness |

## Dependency Ownership Rules

- Keep public sample image tags in `config/service-pipelines.psd1`; do not
  duplicate them in generated Job DSL, Jenkinsfiles, or controller examples.
- Keep the Jenkins controller image, plugin installation, credentials providers,
  security realm, and agent images in controller or future JCasC scope. The
  checked-in Kubernetes manifest is only a public-safe example.
- Keep PowerShell compatibility at PowerShell 7+ unless a repository-local
  validation change proves a newer minimum is required.
- Keep generated dependency artifacts under `out/`. The directory is ignored and
  must not become the source of committed Job DSL or controller state.

## Upgrade Stages

1. Public image catalog refresh

   Update only `config/service-pipelines.psd1` after choosing the new public
   image tags from upstream release notes. Record the chosen tags in the same
   catalog entries that currently own the image names. Keep `HasJenkinsfile =
   $false` for catalog-only examples unless a matching
   `services/<name>/Jenkinsfile` and required files are added in the same change.

   Validate with:

   ```powershell
   pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
   pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
   pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
   ```

   Investigate image-specific changes to exposed ports, default users, health
   endpoints, filesystem paths, startup timing, and environment variables before
   promoting the update to downstream templates.

2. Controller image and plugin baseline

   Treat `k8s/jenkins-controller/jenkins.yaml` as an example, not the source of a
   production controller. Keep controller plugin installation, credentials,
   agents, and security realm in a future JCasC package. Do not change generated
   Job DSL defaults to require a controller plugin until that package documents
   and validates the plugin set.

   If the floating `jenkins/jenkins:lts` example is replaced with a pinned image,
   update `k8s/jenkins-controller/README.md` in the same change so the manifest,
   controller scope, persistence expectations, and validation limits stay aligned.

   Validate the existing controller-free contract with:

   ```powershell
   pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
   ```

   Add live-controller or JCasC validation only when the JCasC files exist.

3. PowerShell and agent-tool baseline

   Keep PowerShell compatibility at 7+ until there is a concrete need for a
   newer runtime. If Jenkins agent images are standardized later, update
   `jenkins/README.md`, the Jenkinsfile preflight expectations, and the testing
   docs together.

   Validate with:

   ```powershell
   pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
   sh scripts/run-phase-validation.sh
   ```

4. Jenkinsfile behavior dependencies

   Add JenkinsPipelineUnit or equivalent local tests only when scripted
   Jenkinsfile logic grows beyond the current declarative wrappers. Keep
   non-dry-run delivery and promotion behind explicit approval and bootstrap
   checks.

## Validation Matrix

| Change package | Minimum validation |
| --- | --- |
| Public image catalog tag refresh | `pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json`; `pwsh -NoProfile -File scripts/validate-service-pipelines.ps1`; `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1` |
| Controller example or JCasC boundary documentation | `pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1`; live controller or JCasC validation only when those files exist |
| Jenkins agent tool baseline | `sh scripts/run-phase-validation.sh`; live Jenkins agent readiness review before rollout |
| Job DSL or Jenkinsfile behavior dependency | `sh scripts/run-phase-validation.sh` |

## Breaking Changes To Investigate

- Sample image tag updates can change exposed ports, startup timing, default
  users, filesystem paths, or health endpoints. Verify downstream examples
  before changing the catalog.
- Moving from the floating Jenkins LTS image to a pinned controller image or a
  JCasC-owned plugin set can reveal plugin compatibility gaps. Keep that change
  separate from public sample service image updates.
- Raising the minimum PowerShell version can break older Jenkins agents even
  when local validation passes on a newer workstation.
- Adding Jenkinsfile-backed services changes `ServiceJobCount` and must update
  service fixtures, required-file checks, generated Job DSL expectations, and
  documentation in the same stage.

## Maintenance Risk Indicators

- `k8s/jenkins-controller/jenkins.yaml` uses `jenkins/jenkins:lts`, which is
  intentionally floating and should be reviewed before production use.
- There is no lockfile or generated dependency snapshot for Jenkins plugins,
  because controller plugins are outside the current template scope.
- Public image tag freshness cannot be determined from repository-local files
  alone. Check image release notes externally before changing tags, then record
  the chosen tags in `config/service-pipelines.psd1`.
- Controller-free validation proves generated Job DSL shape and public-safe
  defaults; it does not prove live Jenkins plugin installation, credential
  providers, agent image contents, or cluster access.
