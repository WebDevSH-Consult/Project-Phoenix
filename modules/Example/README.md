# Example Module

A trivial module that does nothing but prove the [Phoenix Core module contract](../PhoenixCore/README.md) works end to end. `Bootstrap.ps1` registers it today as a placeholder until real modules (Windows Configuration, Application Installer, etc.) land in later sprints.

Copy `Example.psm1` / `Example.psd1` as the starting point for a new module: rename the function, fill in the four script blocks in `Get-<Name>ModuleDefinition`, and register it in `Bootstrap.ps1`.
