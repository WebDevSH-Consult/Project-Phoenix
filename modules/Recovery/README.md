# Recovery

The Recovery / Rollback Engine (ADR [0015](../../docs/adr/0015-recovery-rollback-engine.md), [0017](../../docs/adr/0017-automatic-transactional-rollback.md)) — the **Self-Heal** stage of the [deployment pipeline](../../ARCHITECTURE.md#standard-the-phoenix-deployment-lifecycle). Reverses the changes a deployment made, whether after the fact or automatically mid-run.

```powershell
Invoke-PhoenixRollback -RootPath (Get-Location)   # roll back the most recent deployment report
.\Bootstrap.ps1 -Transactional                    # all-or-nothing run: auto-reverse on any failure
```

## What it reverses

Only **confirmed changes** — each mutating result carries a `Changed` boolean, `$true` only on a verified-successful apply. Skips, dry-runs, elevation-skips, and failures are `Changed = $false` and left untouched (a failed apply's post-state is uncertain — surfaced for inspection, never auto-reversed).

| Change | Reversal | Verified? |
|---|---|---|
| Setting written (WindowsConfig) | Restore `PreviousValue`; or **remove** the value if Phoenix introduced it (previous value was unset) | Re-read confirms the restore |
| Application installed (Installer) | `Uninstall-PhoenixApplication` | Uninstall confirms removal |

## How it works

`Invoke-PhoenixRollback` reads a deployment report (the latest under `reports/`, or `-ReportPath`), joins each `Changed` detail to its manifest — settings to `Get-PhoenixSettingManifest` (for `Path`/`ValueName`/`ValueKind`, which the report doesn't carry), applications to `Get-PhoenixApplicationManifest` — and executes the reversal in **reverse order**: applications first (they installed after settings), then settings, each within reverse discovery order. A changed detail with no matching manifest is skipped with a `WARNING`, not a hard failure.

`Get-PhoenixRollbackPlan` (the plan builder) and the two `Undo-*` primitives are independently usable and fully mockable — no test touches the real registry or a real installer.

## Automatic transactional rollback (ADR 0017)

`Bootstrap.ps1 -Transactional` makes a run **all-or-nothing**: it runs normally, and if any module does not end `Healthy`, Phoenix automatically reverses every confirmed change the run made. It does this through **`Invoke-PhoenixRollbackFromResults -Results -RootPath`** — the in-memory sibling of `Invoke-PhoenixRollback` that reverses a run's live health results instead of a saved report. Both entry points share the *same* plan builder and `Undo-*` primitives (`Invoke-PhoenixRollback` simply loads a report and hands its `Modules` to the results path), so the report-driven and in-run rollbacks can never drift.

The change ledger comes for free: every module surfaces the changes it made through the lifecycle's `GetDetails` channel, so a completed run already knows exactly what to reverse. The forward orchestration path is unchanged.

"Transactional" is bounded honestly — it reverses Phoenix's own recorded, reversible changes (settings, installs), best-effort and verified; a reversal that fails is surfaced, not hidden. It is not an OS snapshot. Opt-in: the default run leaves earlier successful changes in place.

## Not orchestrated

Rollback is a recovery action, not forward deployment, so this module has **no `module.json`** — it's operator-invoked or triggered by the transactional run, never an orchestrated stage of its own.
