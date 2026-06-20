# Job DSL Phase Handoff

Use this handoff to preserve the `job-dsl-coverage` phase evidence that moved
the project into `pipeline-boundary-hardening`. Keep it current when the
controller-free Job DSL gate changes or when boundary-hardening work needs to
show why the previous phase is no longer the active blocker.

## Current Gate

The machine-managed transition gate is the repository-owned wrapper:

```sh
sh scripts/run-phase-validation.sh
```

That wrapper resolves PowerShell, runs the focused public `dev` lane, then runs
the broader controller-free harness:

```powershell
pwsh -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
pwsh -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
```

Generated Job DSL fixtures belong under ignored `out/` paths. Do not commit
generated DSL from a live controller or a real environment.

## Latest Handoff Evidence

The `job-dsl-coverage` transition gate most recently passed in this worktree on
2026-06-20 with:

```sh
sh scripts/run-phase-validation.sh
```

The passing run produced this controller-free evidence:

- dependency inventory reported the manifest-free package posture, four
  public-image service catalog entries, the `jenkins/jenkins:lts` controller
  image reference, and the PowerShell 7+ validation contract;
- the `dev` job plan rendered validation, delivery, and promotion jobs under
  `platform/dev`;
- the service pipeline plan rendered the four public catalog services with
  `HasJenkinsfile = false` and `ServiceJobCount = 0`;
- Job DSL export wrote the seed fixture under ignored `out/jenkins/` while
  keeping repository URL, branch spec, and credentials ID values parameterized;
- service pipeline validation passed for the catalog-only public-image state;
  and
- the aggregate Job DSL harness plus public preset test suite passed for
  individual `dev`, `staging`, and `prod` fixtures, the combined public preset
  matrix fixture, custom selections, nested roots, unsafe root rejection, SCM
  escaping, service-job fixtures, and runtime argument handling.

This evidence was refreshed after the phase controller reported the transition
command as eligible. The phase metadata now records `template-maintenance` as
the active phase, so this handoff remains as the audit trail for the completed
boundary-hardening transition.

For template-maintenance progress checks, the same wrapper is also the
repository-local way to refresh a stale `jenkins validation failed` dashboard
status. A fresh passing run confirms the current checkout still satisfies the
controller-free Jenkins gate; a failing run keeps the first failing wrapper
command as the active blocker.

## Current Maintenance State

The current machine-managed phase is `template-maintenance`, and there is no
pending `next_phase`. The phase manifest keeps the repository-owned wrapper as
the normal validation command for changes that affect generated job topology,
Jenkinsfile runtime contracts, service catalog behavior, dependency inventory
evidence, or phase-readiness wording.

Template-maintenance work should preserve the boundary-hardening contract rather
than broadening the reusable template by default. Select a new phase in
`docs/instructions/phase-gates.json` before adding new Jenkins platform scope.

The completed transition handoff should continue to show three things:

- the exact wrapper command that passed;
- the controller-free evidence produced by the wrapper; and
- the live-controller rollout checks that remain outside the local gate.

## Evidence To Record

Before changing phase metadata, capture the latest local validation result and
confirm these public-safe expectations:

- the dependency inventory reports the manifest-free package posture, public
  service image tags, controller image references, and PowerShell validation
  contract from committed files;
- the `dev` job plan renders validation, delivery, and promotion jobs under the
  configured platform folder;
- the service pipeline plan renders the public catalog without requiring a
  `services/` directory while all catalog entries remain non-Jenkinsfile-backed;
- Job DSL export writes the seed fixture under `out/jenkins/` and keeps
  repository URL, branch spec, and credentials ID values parameterized;
- service pipeline validation passes for the public-image catalog;
- the aggregate Job DSL harness validates the built-in public-safe preset
  matrix individually and as one combined matrix fixture; and
- the public preset test suite covers custom selection, nested roots, unsafe
  root rejection, and runtime argument handling.

If any item fails in future maintenance work, fix the failing controller-free
contract before changing generated job topology, service catalog behavior, or
phase-readiness wording.

## Boundary Hardening Handoff

`pipeline-boundary-hardening` makes ownership boundaries clearer without turning
local validation into a live-controller requirement. Before handing off to
`template-maintenance`, confirm the documentation still keeps focus on:

- keeping Job DSL responsibilities in job planning, folder generation,
  `pipelineJob` generation, SCM parameter names, branch specs, credentials ID
  parameters, lightweight checkout, and removed-job apply guards;
- keeping Pipeline DSL responsibilities in the Jenkinsfiles that own validation,
  delivery, promotion, archive paths, dry-run behavior, manual approval prompts,
  and public-safe live-action guards;
- keeping service catalog responsibilities in public image metadata,
  service-local file expectations, and explicit Jenkinsfile-backed service
  flags; and
- keeping controller, plugin, agent, credentials provider, security realm, and
  JCasC rollout checks separate from the controller-free public defaults.

Use [pipeline-boundaries.md](pipeline-boundaries.md) as the reader-facing map for
those responsibilities.

Once the project enters `template-maintenance`, normal maintenance work should
preserve those boundaries rather than reopening the phase gate. Use the
controller-free wrapper for changes that affect generated job topology,
Jenkinsfile runtime contracts, service catalog behavior, dependency inventory
evidence, or phase-readiness wording. Use narrower validation lanes for
catalog-only, preset-only, or documentation-only changes when the broader
wrapper is not needed.

## Live-Controller Work That Remains Outside The Gate

A passing wrapper run is not approval to apply generated DSL to a production
controller. Before live rollout, verify separately that:

- the Job DSL plugin and any required controller plugins are installed or
  declared in JCasC;
- Jenkins agents provide `pwsh`, `git`, `kubectl`, and `helm` when the selected
  Jenkinsfiles need them;
- `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, and optional
  `SEED_SCM_CREDENTIALS_ID` are supplied as Jenkins seed parameters;
- private values, registry access, cluster context, credentials, and downstream
  deploy implementation exist outside the public defaults; and
- non-dry-run delivery and promotion still require manual approval prompts, and
  any live deployment, Helm repository refresh, or bootstrap status checks are
  supplied by downstream controller or cluster rollout code rather than by the
  public-safe helper scripts.

## Documentation Consistency Checklist

When handoff evidence changes, keep these documents aligned:

- [testing.md](testing.md) for the controller-free validation lane and what it
  proves.
- [maintenance.md](maintenance.md) for change lanes and phase handoff policy.
- [pipeline-boundaries.md](pipeline-boundaries.md) for responsibility ownership.
- [troubleshooting.md](troubleshooting.md) for interpreting a passing local gate
  when live Jenkins rollout still fails.
- [../jenkins/README.md](../jenkins/README.md) and
  [../jenkins/JOB_BLUEPRINT.md](../jenkins/JOB_BLUEPRINT.md) for seed job
  parameters, preset matrix behavior, and Jenkins setup flow.
