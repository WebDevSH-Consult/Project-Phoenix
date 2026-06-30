# Example Module

A trivial module that does nothing but prove the [Phoenix Core module contract](../PhoenixCore/README.md) and the [Bootstrap Engine](../PhoenixBootstrap/README.md) orchestration pipeline work end to end. It is discovered and run automatically via its `module.json` — `Bootstrap.ps1` knows nothing about it directly.

Copy `Example.psm1` / `Example.psd1` / `module.json` as the starting point for a new module: rename the function, fill in the four script blocks in `Get-<Name>ModuleDefinition`, and update `module.json`'s `Name` and `EntryPoint`. No changes to `Bootstrap.ps1` are needed.
