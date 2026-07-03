# 0012 — Installer Preflight Safety Gate

## Status
Accepted

## Context
A real-world AMD driver installation failure (Error 206) traced back to Windows being in a non-idle servicing state: pending file rename operations from earlier installs meant the driver installer could not run safely. The failure class isn't AMD-specific — any system-level installation (WinGet, MSI, EXE, drivers) attempted while Windows has a pending reboot, pending file operations, or another active installer session can fail or half-complete. Phoenix validated hardware and installed applications, but had no **system-state gate between the two**. This is a missing safety layer, not a feature.

## Decision
One universal rule: **no system-level installation runs on a non-idle Windows servicing state.**

Preflight checks live in `modules/Validation` — judging system state is exactly what that module is for — using the existing PASS/FAIL result contract with `Category: 'InstallerPreflight'`:

- `Test-PhoenixPendingReboot` — Component Based Servicing `RebootPending` and Windows Update `RebootRequired` registry keys. Either present → `FAIL`, recommended action: restart before continuing.
- `Test-PhoenixPendingFileOperations` — `PendingFileRenameOperations` under `Session Manager`. Non-empty → `FAIL`, with the count and a sample of the components involved in the message.
- `Test-PhoenixActiveInstaller` — the `Global\_MSIExecute` mutex. Held (or inaccessible, which implies held by another session) → `FAIL`: another installation is in progress.
- `Get-PhoenixPreflightState` — runs all three, returns `{ Safe; Results }`.

All three are HKLM **reads** plus a mutex probe — no elevation required, and each system access goes through a thin mockable wrapper per the repository standard.

**Enforcement**: `Install-PhoenixApplications` (the orchestrated path) and `Invoke-PhoenixProfile` (the explicit path) run the preflight before touching anything. On `FAIL` they log the reasons and return the preflight results as their output — installing nothing — so the failure flows into the module health object and the deployment report through the existing `GetDetails` channel with a clear recommended action. An explicit `-SkipPreflight` switch exists as an operator escape hatch, off by default.

## Alternatives Considered
- **`modules/Validation/Preflight/` as a folder of `.ps1` files** (as originally proposed): rejected — ADR 0007 already decided the one-`.psm1`-per-module convention; a second file-layout convention needs a stronger reason than three functions.
- **A standalone Preflight module**: rejected — it would be a module whose entire content is three validation checks; Validation already owns the PASS/WARN/FAIL vocabulary and result plumbing.
- **Gating inside each backend** (`Install-PhoenixWinGetPackage` etc.): rejected — the state is machine-global, so checking once per batch is correct and checking per backend call is redundant; the per-entry-point gate also produces one clear report entry instead of N duplicates.
- **Adding preflight checks to the system-wide `Invoke-PhoenixValidationReport`**: deferred — that report runs *after* installs (RunOrder 90), where a pending reboot is often the expected *result* of installing, deserving WARN-style semantics rather than the gate's blocking FAIL. Two different questions; conflating them would weaken both.
- **WARN instead of FAIL for pending state**: rejected — the entire lesson of Error 206 is that proceeding anyway fails in confusing ways. Blocking with a clear "restart first" beats a warning nobody reads.

## Consequences
Driver-class installation failures caused by servicing state become a clear, actionable preflight message instead of a mid-install mystery. The gate applies to every current and future backend automatically. After a blocked run, the deployment report states exactly why nothing was installed and what to do (restart). `-SkipPreflight` preserves operator control for the cases the gate can't anticipate.
