# 0015 — Recovery / Rollback Engine

## Status
Accepted

## Context
The deployment pipeline's final stage is **Self-Heal** (ARCHITECTURE.md): repair / retry / rollback. Retry already exists (the Installer), and the building blocks for rollback are present — WindowsConfig records each setting's `PreviousValue`, and the Installer can `Uninstall-PhoenixApplication`. What was missing is the engine that *consolidates* these into a coherent "undo what the last deployment changed" capability. This is the core of EPIC-04 and the last major capability before v1.0.

## Decision
A new module, `modules/Recovery`, reverses the changes a deployment made — driven by the deployment report the run already produces (ADR 0010), joined with the manifests that describe how to reverse each change.

### What "changed" means — an explicit `Changed` flag
Rollback must reverse only changes that were *actually and successfully applied*. Relying on message-string matching ("Applied ...") is fragile, so `Set-PhoenixSetting` and `Install-PhoenixApplication` gain a `Changed` boolean on their result:

- `Changed = $true` only on the confirmed-success apply path (a setting written and verified; an application installed and verified).
- `Changed = $false` for skips (already in desired state, dry-run, elevation-skip) and for failures.

A **failed** apply is deliberately *not* marked `Changed` — its post-state is uncertain, so it is surfaced in the report for inspection rather than auto-reversed. Rollback reverses confirmed changes only.

### Reversal primitives
- `Undo-PhoenixSettingChange` restores a setting: write `PreviousValue` back, or — if the value was previously unset (`PreviousValue` is `$null`) — remove it. Re-reads to verify. Uses WindowsConfig's registry provider plus a new `Remove-PhoenixRegistryValue` wrapper.
- `Undo-PhoenixApplicationInstall` uninstalls via the Installer's `Uninstall-PhoenixApplication`, which already verifies removal.

Both return the standard `{ Category = 'Rollback', Name, Status, Message }` result.

### Orchestration
`Invoke-PhoenixRollback -RootPath [-ReportPath]` loads a deployment report (the latest under `reports/` if unspecified), builds a rollback plan by joining each `Changed` detail to its manifest (settings → `Get-PhoenixSettingManifest` for `Path`/`ValueName`/`ValueKind`; applications → `Get-PhoenixApplicationManifest`), and executes it in **reverse order** — applications first (they installed last, at `RunOrder 50`), then settings (changed earlier, at `40`).

### Not orchestrated
Rollback is a recovery action, **not** a forward-deployment stage, so `Recovery` carries no `module.json` — it is operator-invoked (`Invoke-PhoenixRollback`), like uninstall. Automatic rollback-on-failure within a run is intentionally deferred: it needs cross-module transactional state that would reshape orchestration, and the explicit engine is the right first step.

## Alternatives Considered
- **A separate on-disk change journal** written by every mutating module: rejected for now — the deployment report already records what changed with the needed data; a parallel journal would duplicate it and require wiring a journal primitive into every module (a `Recovery` reverse-dependency). Revisit if rollback needs to survive report rotation or predate reporting.
- **Message-string matching to detect changes**: rejected — fragile. The explicit `Changed` flag is robust and also makes the report itself clearer.
- **Auto-rollback when a module fails mid-run**: deferred (see above) — valuable, but a larger orchestration change than this engine.
- **Rolling back failed/partial applies**: rejected — an unverified post-state is unsafe to auto-reverse; surface it for inspection instead.

## Consequences
`Invoke-PhoenixRollback` can undo a deployment: settings return to their prior values (or are removed if Phoenix introduced them), and applications Phoenix installed are uninstalled — each verified, all in the shared vocabulary, fully mockable in tests. The Self-Heal stage of the pipeline is now real. Remaining EPIC-04 work (auto-remediation, drift detection) builds on this engine rather than inventing new machinery.
