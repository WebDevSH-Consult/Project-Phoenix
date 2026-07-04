# 0014 — Installer Completeness: Dry-Run, Upgrade, Uninstall

## Status
Accepted

## Context
The Application Deployment Engine (ADR 0007) could install and re-validate, but a production provisioning tool needs three more operations: a **dry-run** to preview what a run would change, **upgrade** to move installed applications forward, and **uninstall** to remove them. These round out the engine without expanding its scope — they operate on the same manifests, backends, and result vocabulary already in place.

## Decision
All three reuse the existing manifest, backend-wrapper, and `{ Category, Name, Status, Message }` result patterns.

### Dry-run
A `-DryRun` switch on `Install-PhoenixApplication`, `Install-PhoenixApplications`, and `Invoke-PhoenixProfile`. In dry-run **no backend is ever invoked**; each application is evaluated against its `Validate` probes and reports the *plan*:

- Already satisfied → `PASS` ("would take no action").
- Not satisfied → `WARN` ("would install via <backend>").

`WARN` is deliberate: a dry-run surfaces drift (what isn't in the desired state) without failing — the module's `Verify` stage only fails on `FAIL`, so a dry-run of the orchestrated bootstrap stays `Healthy` while every pending change shows as a warning in the deployment report. Dry-run also **skips the preflight gate** (ADR 0012): a preview changes nothing, so servicing-state safety is irrelevant to it.

### Upgrade
`Update-PhoenixApplication` upgrades an already-installed application. The WinGet backend (`winget upgrade`) is fully supported; a not-installed application reports `WARN` ("nothing to upgrade — use install"), and non-WinGet backends report `WARN` ("upgrade not supported for the <backend> backend") rather than silently doing nothing. All six shipped manifests are WinGet.

### Uninstall
`Uninstall-PhoenixApplication` removes an application and **verifies** it is actually gone afterward — symmetric with install's post-action re-validation. WinGet (`winget uninstall`) and MSI (`msiexec /x`) are supported; EXE reports `WARN` ("uninstall not supported for the EXE backend"), since a silent EXE installer exposes no standard uninstall path. Uninstalling a not-installed application is idempotent: `PASS` ("nothing to uninstall").

### Scope boundaries
- **Upgrade and uninstall are operator-invoked utilities**, not part of the orchestrated bootstrap run — bootstrap provisions toward a desired state (install/configure), it doesn't remove things. They're exported for direct or scripted use.
- **Dry-run is not threaded through `Bootstrap.ps1`/orchestration** in this change — that would require a run-wide preview mode across every module and belongs with the future recovery/reporting work. Here it's available on the three install entry points an operator calls directly.

## Alternatives Considered
- **PowerShell `-WhatIf` / `SupportsShouldProcess`**: idiomatic, but the engine's contract is structured result objects that flow into the deployment report, not console `ShouldProcess` messages. An explicit `-DryRun` returning the same result shape is testable and composable; `-WhatIf` output is neither.
- **A new `DRYRUN` status value**: rejected — the PASS/WARN/FAIL vocabulary is shared across every module and report; adding a status just for previews would fragment it. "Would change" maps cleanly onto `WARN` (drift, not failure).
- **Emulating EXE uninstall by scraping the registry uninstall string**: rejected as fragile and out of scope; a clear "not supported" is more honest than a best-effort guess. Revisit if an EXE-installed application actually ships.

## Consequences
Operators can preview a run before committing (`-DryRun`), keep applications current (`Update-PhoenixApplication`), and cleanly remove them (`Uninstall-PhoenixApplication`) — all through the same manifests and vocabulary, all fully mockable in tests (no test runs a real installer). The engine is feature-complete for v1.0; remaining installer work is resilience (recovery/rollback), not new operations.
