# Recovery

The Recovery / Rollback Engine (ADR [0015](../../docs/adr/0015-recovery-rollback-engine.md)) — the **Self-Heal** stage of the [deployment pipeline](../../ARCHITECTURE.md#standard-the-phoenix-deployment-lifecycle). Reverses the changes a deployment made.

```powershell
Invoke-PhoenixRollback -RootPath (Get-Location)   # roll back the most recent deployment report
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

## Not orchestrated

Rollback is a recovery action, not forward deployment, so this module has **no `module.json`** — it's operator-invoked, like uninstall. Automatic rollback-on-failure within a run is deferred (ADR 0015): it needs cross-module transactional state; this engine is the foundation it will build on.
