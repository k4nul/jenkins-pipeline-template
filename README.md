# Jenkins Pipeline Template

Reusable Jenkins pipeline, CI/CD, and Job DSL templates for the DevOps template set.

## Layout

- `jenkins/`: repository validation, bundle delivery, promotion, and seed Jenkinsfiles
- `scripts/`: Job plan, Job DSL export, and service pipeline helpers
- `config/`: reusable environment and service pipeline catalogs
- `k8s/jenkins-controller/`: optional in-cluster Jenkins controller manifests

## Typical Commands

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

Keep repository URLs, credentials IDs, branch specs, and approval behavior parameterized before applying the template to a real project.
