# Maintainer Onboarding

Use this guide when you are new to this Jenkins template and need to produce
local, controller-free evidence before changing Job DSL, Jenkinsfiles, presets,
profiles, or service pipeline metadata.

## First Local Check

Install PowerShell 7 or newer so `pwsh` is available. If your shell does not
expose `pwsh`, set `POWERSHELL_BIN` to the absolute PowerShell path.

Run the repository-owned wrapper from the repository root:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper resolves PowerShell from `POWERSHELL_BIN`, `PWSH`, `PATH`, and
common local install paths. It runs the current public-safe validation lane:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
```

Generated Job DSL fixtures are written under ignored `out/` paths. Do not commit
generated controller output or generated DSL from a real environment.

## What A Passing Run Means

A passing wrapper run is evidence that the public template can render and
validate its controller-free contract:

- the dependency inventory can report package-manager manifest absence, public
  service image tags, controller image references, CI action references, and
  the PowerShell validation contract from committed files;
- the `dev` job plan renders the validation, delivery, and promotion bundle
  jobs under the `platform/dev` folder;
- the service catalog can be planned and validated in its current public-image
  state without requiring a `services/` directory;
- Job DSL export can write a public-safe fixture while keeping repository URL,
  branch spec, and credentials ID values parameterized;
- the aggregate harness validates the built-in public-safe preset matrix both
  as individual preset fixtures and as one combined matrix fixture; and
- the public preset test suite covers custom selection and safety boundaries.

This is not live-controller approval. It does not prove Jenkins plugins,
controller JCasC, agent tools, credentials, registry access, cluster access, or
non-dry-run delivery and promotion are ready.

## Safe Defaults To Preserve

- Keep SCM repository URLs, branch specs, and credentials IDs parameterized.
- Keep company-specific values, private registry details, and real controller
  output out of committed files.
- Keep non-dry-run delivery and promotion behind manual Jenkins approval prompts
  and public-safe script guardrails. Live deployment, Helm repository refresh,
  and bootstrap status checks are downstream rollout responsibilities, not
  behavior implemented by the checked-in public template helpers.
- Keep generated fixtures under `out/`.
- Treat public image catalog examples as catalog metadata unless a service
  explicitly sets `HasJenkinsfile = $true` and provides
  `services/<name>/Jenkinsfile`.

## Where To Go Next

Use the narrowest guide for the work you are about to do:

- [testing.md](testing.md): command details, what the harness proves, and what it
  does not prove.
- [maintenance.md](maintenance.md): change lanes for presets, profiles, service
  catalog entries, Job DSL export, Jenkinsfiles, and tooling.
- [phase-handoff.md](phase-handoff.md): completed transition evidence and the
  place to refresh proof when template-maintenance progress checks need a
  current passing wrapper run.
- [pipeline-boundaries.md](pipeline-boundaries.md): ownership map for Job DSL,
  Pipeline DSL, service catalog metadata, and controller/JCasC rollout.
- [troubleshooting.md](troubleshooting.md): common local failures and live
  controller rollout interpretation.
- [../jenkins/README.md](../jenkins/README.md): seed job parameters and Jenkins
  setup flow.

Before applying generated DSL in Jenkins, provide `SEED_REPO_URL`,
`SEED_BRANCH_SPEC`, and optional `SEED_SCM_CREDENTIALS_ID` as seed parameters.
The template intentionally does not assume a fixed branch name or credentials ID.
