# Contributing to Jenkins Pipeline Template

This project is a reusable Jenkins pipeline and Job DSL template. Keep
repository URLs, branch specs, credential IDs, environments, and approval gates
parameterized.

## Local Setup

```powershell
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
```

Use `scripts/validate-jenkins-job-dsl.ps1` as the first controller-free
regression check when job planning, Job DSL export, environment presets, profiles,
or service pipeline catalog data change. Use `scripts/validate-service-pipelines.ps1`
directly when you only need the service catalog check.

## Pull Request Checklist

- Do not commit generated `out/` files, local credentials, or private controller details.
- Keep credential IDs as parameters or documented placeholders.
- Keep production or destructive actions behind approval gates.
- Update `jenkins/JOB_BLUEPRINT.md` when pipeline contract behavior changes.

## Template Policy

Examples should run as public templates. Avoid embedding organization names,
private SCM URLs, real credentials IDs, or fixed branch policies.
