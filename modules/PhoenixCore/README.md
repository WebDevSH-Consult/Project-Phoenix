# PhoenixCore

The lifecycle dispatcher every Phoenix module runs through. See [ARCHITECTURE.md](../../ARCHITECTURE.md) for the full diagram — no module talks to another module directly; everything routes through here.

## Module Contract

A module is any hashtable with up to four script blocks, passed to `Invoke-PhoenixModuleLifecycle`:

| Stage      | Script block | Contract                                                              |
|------------|--------------|------------------------------------------------------------------------|
| Initialise | `Initialize` | Load state/config. No return value expected.                          |
| Validate   | `Validate`   | Return `$true`/`$false`. `$false` aborts the run as an Error.          |
| Execute    | `Execute`    | Perform the actual work. No return value expected.                    |
| Verify     | `Verify`     | Return `$true`/`$false`. `$false` marks the run as a Warning, not an Error. |

`Log` and `Report` are handled automatically — every stage transition is logged via `Write-PhoenixLog`, and the function returns a health object:

```powershell
[PSCustomObject]@{
    Module        = 'Example'
    Status         = 'Healthy' # Healthy | Warning | Error | Unknown
    HealthPercent  = 100
    LastRun        = '2026-06-26T09:14:21.0000000+00:00'
    Issues         = @()
}
```

See [modules/Example](../Example/README.md) for a minimal module implementing this contract — copy it as a starting point for new modules.

## Running a batch of modules

`Invoke-PhoenixBootstrap -Modules @(...)` runs each module hashtable through the lifecycle in order and logs an aggregate health report. This is what `Bootstrap.ps1` calls.

## Version reporting

`Get-PhoenixVersion -RootPath <repo root>` reads the `VERSION` file (the single source of truth for the project's version) and returns `Version`, `Major`, `Minor`, and `Patch`. `Bootstrap.ps1` calls this at startup to log the running version, and exposes a `-Version` switch that prints it and exits without running any modules.
