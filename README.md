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
- `docs/`: local validation and troubleshooting guidance
- `k8s/jenkins-controller/`: optional in-cluster Jenkins controller manifests

## Typical Commands

```powershell
.\scripts\validate-jenkins-job-dsl.ps1
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\show-service-pipeline-plan.ps1 -Format json
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
.\scripts\validate-service-pipelines.ps1
```

Use `validate-jenkins-job-dsl.ps1` before changing job planning, Job DSL export, environment presets, profiles, or service pipeline catalog data. It validates the built-in public-safe preset matrix and writes generated fixtures only under ignored `out/` paths.

Keep repository URLs, credentials IDs, branch specs, and approval behavior parameterized before applying the template to a real project.

See [docs/testing.md](docs/testing.md) for the controller-free validation lane
and [docs/troubleshooting.md](docs/troubleshooting.md) for common local failures.
Use [docs/dependency-plan.md](docs/dependency-plan.md) when planning public image,
Jenkins controller, PowerShell runtime, or Jenkins agent tool updates.
