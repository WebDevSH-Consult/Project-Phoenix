# Validation

The System Validation engine (see [EPIC-04](../../docs/roadmap/EPIC-04-System-Validation.md)). Discovered and run automatically by the [Bootstrap Engine](../PhoenixBootstrap/README.md) via its `module.json`, at `RunOrder: 90` so it runs after other modules — validating what was just installed/configured, not before.

## Contract

Every check returns a structured result, logged via `Write-PhoenixLog` as it runs:

```powershell
[PSCustomObject]@{
    Category = 'Hardware'   # Hardware | Windows | Drivers | Gaming | AI | ...
    Name     = 'GPU'
    Status   = 'PASS'       # PASS | WARN | FAIL
    Message  = 'Detected: AMD Radeon RX 7900 XT [AMD]'
}
```

- **PASS** — confirmed working.
- **WARN** — present but not fully confirmed, or intentionally absent (e.g. a Store package that isn't expected on every workstation profile). Never treated as a failure.
- **FAIL** — missing something required. Marks the module `Warning` in the aggregate health report (see [PhoenixCore](../PhoenixCore/README.md)).

## What's implemented today

- `Test-PhoenixGpu` — detects installed GPUs via `Get-CimInstance Win32_VideoController` and reports vendor (AMD/NVIDIA/Intel) **without assuming** which one is present. An unrecognised adapter name is `WARN`, not silently ignored or guessed at.
- `Test-PhoenixCommandAvailable` — generic PATH-command check (used for `winget`, `git`).
- `Test-PhoenixAppxPackageAvailable` — generic Microsoft Store package check. Absence is `WARN`, never `FAIL` — Phoenix never assumes a Store package exists or is expected.
- `Test-PhoenixPathExists` — generic filesystem path check. Absence is `WARN`.
- `Test-PhoenixWinGetPackageInstalled` — generic check via `winget list`. Absence is `WARN`. Used by [modules/Installer](../Installer/README.md) as one of its application-detection probes — the concrete mechanism behind "once installers exist, validation can check them automatically."

## What's intentionally not implemented yet

GameBar, Rockstar, Xbox Services, URI handler, and AI-tooling checks are **not** built yet — no installer module exists for them yet either. Steam/Epic/Git/VS Code/7-Zip/PowerShell now have manifests in [modules/Installer](../Installer/README.md), which reuses this module's `Test-Phoenix*` probes for its own install/verify flow. See [EPIC-04](../../docs/roadmap/EPIC-04-System-Validation.md) for the full planned scope.

## Adding a new check

1. Write a `Test-Phoenix<Thing>` function that returns a result via `New-PhoenixValidationResult` (private, module-internal helper).
2. Add it to `Invoke-PhoenixValidationReport`.
3. Add hardware/software detection logic to the check itself, never to the caller — the caller should never need to know or guess what's installed.
4. Add Pester coverage mocking whatever OS/hardware API the check calls, so CI passes regardless of the runner's actual hardware.
