# Troubleshooting

Use this page for local Jenkins template validation failures before involving a
live Jenkins controller.

## `pwsh` Is Not Found

Install PowerShell 7 or newer and retry the command with `pwsh -NoProfile`.
The repository validation scripts are PowerShell scripts and are not expected to
run through `bash` directly.

For automation, use `sh scripts/run-phase-validation.sh` or set
`POWERSHELL_BIN` to the absolute `pwsh` path. The wrapper also checks `PWSH`,
`$HOME/.local/bin/pwsh`, and common system install paths so cron-style shells do
not fail only because their `PATH` omits a local PowerShell install.

## `OutputPath must resolve under the repository out directory`

Plan and export scripts only write generated artifacts under `out/`. Use paths
such as `out/jenkins/seed-job-dsl.groovy` or `out/jenkins/validation`.

## Generated Job DSL Contains A Real SCM URL

The default export should use `REPLACE_WITH_REPOSITORY_URL` and
`REPLACE_WITH_BRANCH_SPEC` placeholders. Pass `-RepoUrl`, `-BranchSpec`, and
`-ScmCredentialsId` only for local inspection or from Jenkins seed parameters,
and keep those values out of committed documentation and fixtures.

## `No services directory found`

This message is expected for the current public-image catalog because
`config/service-pipelines.psd1` marks every service as `HasJenkinsfile = $false`.
It becomes a failure only when a catalog entry expects a Jenkinsfile-backed
service and the matching `services/<name>` directory is missing.

## Job Plans Mention `invoke-*` Scripts

`scripts/show-jenkins-job-plan.ps1` includes local command fields for the
repository validation, delivery, and promotion jobs. Treat those command strings
as the Pipeline DSL contract for Jenkins runtime entrypoints. The controller-free
validation lane in [testing.md](testing.md) verifies job planning, generated DSL,
SCM placeholder safety, and service catalog consistency; it does not execute a
live repository validation or delivery entrypoint.

The checked-in Jenkinsfiles also reference runtime helpers such as
`scripts/validate-workstation.ps1` and environment value files such as
`config/platform-values.dev.env`. Those files are not part of the current
controller-free harness, so a live Jenkins rollout must provide or implement
them before enabling validation, delivery, or promotion jobs.

## Service Jobs Do Not Appear

Service jobs are generated only for catalog entries that set
`HasJenkinsfile = $true`. The current public-image examples do not require
dedicated image build jobs, so `ServiceJobCount` is expected to be `0`.
If you are adding a Jenkinsfile-backed service, update the service catalog,
`services/<name>/Jenkinsfile`, and required-file expectations together; see
[maintenance.md](maintenance.md) for the complete service catalog change lane.
