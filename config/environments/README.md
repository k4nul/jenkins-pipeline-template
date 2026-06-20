# Environment Presets

English | [한국어](README.ko.md)

This directory contains reusable environment presets that reduce repeated
arguments for validation, delivery, promotion, and values scaffold scripts.
Presets also drive generated Jenkins folder names, job parameters, archive
paths, and promotion paths in the Job DSL plan/export flow.

## Included Presets

- `dev.psd1`: development-friendly web-platform baseline
- `staging.psd1`: broader shared-services baseline for pre-production checks
- `prod.psd1`: production-oriented shared-services baseline

## What A Preset Usually Controls

- `Description`: human-readable selection summary used in generated plans
- `ValuesFile`: default values file path
- `Version`: default image tag or validation tag
- `Profile`: default bundle profile
- `Applications`: default application selection
- `DataServices`: default data service selection
- `IncludeJenkins`: whether the selected bundle should include Jenkins components
- `OutputPath`: default rendered bundle output path for delivery workflows
- `ArchivePath`: default ZIP archive path for delivery or promotion workflows
- `PromotionExtractPath`: default extraction path for promotion workflows

The current checked-in presets use public images and do not set `DockerRegistry`.
The scripts still accept a registry override when a downstream template adds
private images. The `ValuesFile` entries point at tracked `.env.example` files
so generated Jenkins jobs have a public-safe runtime contract by default. Copy
those examples to ignored `config/platform-values*.env` files before adding
private, environment-specific values downstream.

## How To Use A Preset

Example:

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

Omit `-EnvironmentPreset` to preview or export the full public preset matrix
that `job-seed.Jenkinsfile` uses when `SEED_ENVIRONMENT_PRESETS` is blank.

Presets act as shared defaults, not hard locks. Explicit script arguments still
override preset values.

Run the Jenkins Job DSL harness after changing a preset:

```powershell
.\scripts\validate-jenkins-job-dsl.ps1
```

That means you can start from `dev` and still override:

- profile
- application list
- data service list
- output paths

without editing the preset file immediately.

The generated plan includes repository validation, delivery, and promotion
command fields for Jenkins runtime jobs. Use [../../docs/testing.md](../../docs/testing.md)
for the local controller-free validation lane that exists in this repository.
