# Jenkins Pipeline Template

Reusable Jenkins pipeline, CI/CD, and Job DSL templates for the DevOps template set.

## Open Source

This repository is prepared for public collaboration under the [MIT License](LICENSE).
See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening issues or pull requests.
Do not commit Jenkins credentials, private SCM URLs, controller-specific output,
or generated Job DSL for a real environment.

## Layout

- `jenkins/`: repository validation, bundle delivery, promotion, and seed Jenkinsfiles
- `scripts/`: Job plan, Job DSL export, and service pipeline helpers
- `config/`: reusable environment and service pipeline catalogs
- `docs/`: onboarding, local validation, maintenance, and troubleshooting guidance
- `k8s/jenkins-controller/`: optional in-cluster Jenkins controller manifests

## Typical Commands

Automation and phase validation use the repository-owned wrapper:

```sh
sh scripts/run-phase-validation.sh
```

```powershell
.\scripts\show-dependency-inventory.ps1 -Format json
.\scripts\validate-jenkins-job-dsl.ps1
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\show-service-pipeline-plan.ps1 -Format json
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
.\scripts\export-jenkins-job-dsl.ps1 -OutputPath .\out\jenkins\public-preset-matrix-seed-job-dsl.groovy
.\scripts\validate-service-pipelines.ps1
.\tests\jenkins-job-dsl.public-presets.ps1
```

Use `validate-jenkins-job-dsl.ps1` before changing job planning, Job DSL export, environment presets, profiles, or service pipeline catalog data. It validates the built-in public-safe preset matrix and writes generated fixtures only under ignored `out/` paths.
Omit `-EnvironmentPreset` from plan or export commands when you need to preview
the same full public-safe preset matrix that the seed job uses by default.
The phase wrapper labels each validation step, reports the first failing command,
and is also run by the `Jenkins Phase Validation` GitHub Actions workflow.
Use `show-dependency-inventory.ps1` before image, controller, or toolchain
planning so the dependency posture is based on committed catalog and Kubernetes
manifest evidence.

Keep repository URLs, credentials IDs, branch specs, and approval behavior parameterized before applying the template to a real project.

Start with [docs/onboarding.md](docs/onboarding.md) if you are setting up a
fresh checkout or preparing first validation evidence. See
[docs/testing.md](docs/testing.md) for the controller-free validation lane and
[docs/maintenance.md](docs/maintenance.md) for the Job DSL maintenance runbook,
including the Job DSL, Pipeline DSL, and controller/JCasC responsibility
boundaries preserved in the current `template-maintenance` phase. Use
[docs/phase-handoff.md](docs/phase-handoff.md) when recording or refreshing the
passed controller-free evidence from the completed
`pipeline-boundary-hardening` to `template-maintenance` handoff.
Use [docs/validation-evidence.md](docs/validation-evidence.md) when a progress
dashboard or maintenance report still says `jenkins validation failed` and you
need the exact controller-free evidence refresh workflow before changing phase
wording.
Use [docs/pipeline-boundaries.md](docs/pipeline-boundaries.md)
as the focused guide for deciding whether a change belongs in Job DSL generation,
Pipeline DSL execution, service catalog metadata, or live controller/JCasC
rollout. Use
[docs/troubleshooting.md](docs/troubleshooting.md) for common local failures and
for interpreting a passing local phase gate that still needs live-controller
rollout checks.
Use [docs/dependency-plan.md](docs/dependency-plan.md) when planning public image,
Jenkins controller, PowerShell runtime, or Jenkins agent tool updates.
