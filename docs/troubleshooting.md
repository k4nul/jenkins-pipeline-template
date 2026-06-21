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
When PowerShell is found, the wrapper prints the resolved path and version to
stderr before running the validation steps.

## `OutputPath must resolve under the repository out directory`

Plan and export scripts only write generated artifacts under `out/`. Use paths
such as `out/jenkins/seed-job-dsl.groovy` or `out/jenkins/validation`.

## Generated Job DSL Contains A Real SCM URL

The default export should use `REPLACE_WITH_REPOSITORY_URL` and
`REPLACE_WITH_BRANCH_SPEC` placeholders. Pass `-RepoUrl`, `-BranchSpec`, and
`-ScmCredentialsId` only for local inspection or from Jenkins seed parameters,
and keep those values out of committed documentation and fixtures. Branch specs
are intentionally constrained to common Jenkins Git patterns such as
`*/main`, `*/release-1`, or `refs/heads/main`; whitespace, quotes, and other
expression-like characters fail closed before DSL generation. SCM credentials
IDs are also constrained to simple identifier characters and should refer to
Jenkins-managed credentials, not embedded credential material.

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
SCM placeholder safety, service catalog consistency, committed runtime helper
scripts, and tracked public-safe values defaults.

The checked-in runtime entrypoints are public-safe contract helpers. Delivery
can write a `bundle-manifest.json` and archive under `out/`, and promotion can
extract and verify that archive. They intentionally do not perform non-dry-run
cluster deployment, Helm repository updates, or live bootstrap status checks.
Those actions require a downstream implementation or controller rollout lane.

## Live Delivery Or Promotion Fails Closed

The public-safe helper scripts intentionally stop before live actions that need
a real controller, Helm configuration, registry access, or cluster context.
These messages are expected until a downstream rollout lane implements the live
behavior:

- `Non-dry-run bundle deployment is not implemented...`
- `Non-dry-run bundle promotion deployment is not implemented...`
- `PrepareHelmRepos is a live Helm action...`
- `RequireBootstrapStatus needs a live cluster...`

Keep `DeploymentDryRun` enabled for the reusable template path. If a real
environment needs non-dry-run deployment, Helm repository preparation, or
bootstrap status checks, add that behavior in the downstream controller or
cluster rollout package and validate it outside the controller-free template
gate.

## Phase Validation Passes But Jenkins Rollout Is Not Ready

`sh scripts/run-phase-validation.sh` is a local phase gate for public-safe Job
DSL coverage. A passing result proves the `dev` dashboard lane, service catalog
plan, Job DSL export, service validation, individual preset fixtures, the
combined full preset matrix fixture, public preset test suite, and committed
runtime contract can run without a Jenkins controller.

It does not prove that a live controller is ready. Before applying generated DSL
outside the local fixture, separately verify:

- the Job DSL plugin and any controller plugins are installed or declared in
  JCasC;
- Jenkins agents provide `pwsh`, `git`, `kubectl`, and `helm` as needed by the
  selected Jenkinsfiles;
- `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, and optional `SEED_SCM_CREDENTIALS_ID`
  are set as Jenkins parameters rather than committed values;
- private values, credentials, registry access, cluster context, and any
  downstream render/deploy implementation are available outside the public
  defaults;
- non-dry-run delivery and promotion still require the manual approval prompts.

If the local phase gate passes but Jenkins fails while applying DSL or running a
job, troubleshoot that as a controller, plugin, agent, credential, or target
repository rollout issue rather than weakening the public-safe defaults. Use
[phase-handoff.md](phase-handoff.md) to record the local evidence before a
phase-transition task updates phase metadata.

## Dashboard Still Says `jenkins validation failed`

Treat the progress dashboard as a cached signal until you compare it with a
fresh local wrapper run:

```sh
sh scripts/run-phase-validation.sh
```

If the wrapper passes, the current checkout has satisfied the controller-free
Jenkins validation lane even if an older dashboard snapshot still says
`jenkins validation failed`. Refresh [phase-handoff.md](phase-handoff.md) with
the passing command and the evidence summary when a maintenance run needs to
make that status change auditable. Use
[validation-evidence.md](validation-evidence.md) for the refresh checklist and
for the claims that must remain outside the controller-free evidence.

If the wrapper fails, use the first `Phase validation failed during "<label>"`
message as the active blocker. The wrapper prints the failed label, exit code,
and command before exiting. Common causes are a missing PowerShell runtime,
invalid generated `out/` path, unsafe SCM input, a read-only checkout that
cannot write ignored validation fixtures under `out/`, a service catalog entry
that expects a missing `services/<name>/Jenkinsfile`, or a changed
Jenkinsfile/runtime helper that no longer matches the public-safe assertions.
Fix that repository-local failure before changing phase-readiness wording or
live-controller rollout guidance.

For GitHub Actions failures, open the `Jenkins Phase Validation` workflow run
and inspect the `jenkins-validation-fixtures` artifact when it exists. Those
files are generated from ignored `out/jenkins/**` paths and are diagnostic
evidence only; do not commit them as controller output.

## Service Jobs Do Not Appear

Service jobs are generated only for catalog entries that set
`HasJenkinsfile = $true`. The current public-image examples do not require
dedicated image build jobs, so `ServiceJobCount` is expected to be `0`.
If you are adding a Jenkinsfile-backed service, update the service catalog,
`services/<name>/Jenkinsfile`, and required-file expectations together; see
[maintenance.md](maintenance.md) for the complete service catalog change lane.
