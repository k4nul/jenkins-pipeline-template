# Validation Evidence Refresh

Use this guide when the repository is in `template-maintenance` and a progress
dashboard, handoff note, or maintenance report still says
`jenkins validation failed`. The goal is to refresh controller-free evidence
without changing Jenkins phase metadata or implying that a live controller is
ready.

## Refresh Workflow

Run the repository-owned wrapper from the repository root:

```sh
sh scripts/run-phase-validation.sh
```

The wrapper resolves PowerShell from `POWERSHELL_BIN`, `PWSH`, `PATH`, and
common local install paths. It prints the resolved PowerShell runtime, labels
each validation step, and stops on the first failing command.

When the wrapper passes, record the refreshed evidence in
[phase-handoff.md](phase-handoff.md) only when a handoff, progress report, or
maintenance note needs an auditable explanation that the stale dashboard blocker
is no longer current. Do not edit `docs/instructions/phase-gates.json` unless a
separate phase-transition task has selected a new phase and transition command.

When the wrapper fails, keep the first failing wrapper label as the active
blocker. Do not replace that blocker with a narrower command result unless the
wrapper failure has already been fixed.

## Evidence To Capture

For a passing refresh, capture the command, date, and this evidence summary:

- dependency inventory rendered from committed catalog and controller manifest
  data;
- the `dev` job plan rendered validation, delivery, and promotion jobs under
  the public-safe platform folder;
- the service pipeline plan and validator accepted the catalog-only public-image
  state without requiring a `services/` directory;
- Job DSL export wrote an ignored fixture under `out/jenkins/` while keeping
  repository URL, branch spec, and credentials ID values parameterized;
- the aggregate Job DSL harness covered every public preset and the combined
  public preset matrix; and
- the public preset test suite passed for custom selection, unsafe root
  rejection, service-job fixture, and runtime argument behavior.

This evidence belongs in documentation or reports, not in generated DSL
fixtures. Keep generated files under ignored `out/` paths.

## Latest Refresh

The latest repository-local refresh passed on 2026-06-22 with PowerShell 7.6.2:

```sh
sh scripts/run-phase-validation.sh
```

The run covered dependency inventory, the focused `dev` job plan, service
pipeline plan, ignored Job DSL export, service pipeline validation, aggregate
Job DSL validation, and the public preset test suite. The generated evidence
remained under ignored `out/jenkins/` paths, and no phase metadata was changed.

## What Not To Claim

A passing refresh does not prove live Jenkins readiness. Keep these checks
outside the controller-free evidence:

- Job DSL plugin installation or controller plugin baselines;
- JCasC security, credentials, or agent configuration;
- private SCM, registry, credential, or cluster access;
- non-dry-run delivery or promotion; and
- downstream Helm repository refresh, deployment, or bootstrap status behavior.

Use [pipeline-boundaries.md](pipeline-boundaries.md) when deciding whether a
future change belongs in Job DSL generation, Pipeline DSL execution, service
catalog metadata, or controller/JCasC rollout.
