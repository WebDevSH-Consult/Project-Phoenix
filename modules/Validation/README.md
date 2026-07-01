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

## What's intentionally not implemented yet

Steam, Epic, GameBar, Rockstar, Xbox Services, URI handler, and AI-tooling checks are **not** built yet. Each lands alongside the installer module it validates (Roadmap 0.6+), so it can be tested against a real installation rather than assumed to exist. See [EPIC-04](../../docs/roadmap/EPIC-04-System-Validation.md) for the full planned scope.

## Adding a new check

1. Write a `Test-Phoenix<Thing>` function that returns a result via `New-PhoenixValidationResult` (private, module-internal helper).
2. Add it to `Invoke-PhoenixValidationReport`.
3. Add hardware/software detection logic to the check itself, never to the caller — the caller should never need to know or guess what's installed.
4. Add Pester coverage mocking whatever OS/hardware API the check calls, so CI passes regardless of the runner's actual hardware.
