# 0006 — Module Manifests and the Bootstrap Orchestration Engine

## Status
Accepted

## Context
Through v0.2.0–0.4.0, `Bootstrap.ps1` hard-coded which workstation modules to run (just the `Example` module). Every new module — Steam, Epic, PowerToys, Windows tweaks, AI tooling — would have required editing `Bootstrap.ps1` directly to import it and add it to the run list. That contradicts the architecture's own stated principle (see [ARCHITECTURE.md](../../ARCHITECTURE.md)) that no module should need special-case knowledge baked into the entry point.

## Decision
Every orchestrated module gets a `module.json` manifest in its folder: `Name`, `Version`, `Dependencies`, `RunOrder`, `Enabled`, `EntryPoint`. A new module, `modules/PhoenixBootstrap`, implements the orchestration pipeline:

1. `Get-PhoenixModuleManifest` discovers every `modules/*/module.json` and validates required fields.
2. `Resolve-PhoenixModuleOrder` topologically sorts the enabled manifests by `Dependencies`, breaking ties with `RunOrder` then `Name`.
3. `Invoke-PhoenixOrchestration` imports each module's `.psd1` in that order, calls its declared `EntryPoint` to obtain the lifecycle definition, and hands the full batch to the existing `Invoke-PhoenixBootstrap` (from `modules/PhoenixCore`) for execution, logging, and the aggregate health report.

`Bootstrap.ps1` now only imports the engine modules (`PhoenixLogging`, `PhoenixCore`, `PhoenixConfig`, `PhoenixBootstrap`) and calls `Invoke-PhoenixOrchestration` — it contains no reference to `Example` or any future module by name.

Engine modules themselves do not carry a `module.json` and are not orchestrated; they are infrastructure that `Bootstrap.ps1` imports directly, the same way it always has.

## Alternatives Considered
- **Keep hard-coding new modules into `Bootstrap.ps1` as they're added**: rejected — this is exactly the maintenance burden the Bootstrap Engine milestone (Roadmap 0.5) exists to remove.
- **Store orchestration metadata in the PowerShell module manifest's (`.psd1`) `PrivateData`** instead of a separate `module.json`: rejected. It would conflate two different concerns — PowerShell's own module metadata (exported functions, `ModuleVersion` for PowerShell tooling) versus Phoenix-specific orchestration metadata (dependency graph, enable/disable, run order). A plain JSON file is also more consistent with the rest of `configs/` and easier to read/diff without PowerShell-specific syntax.
- **Convention-based entry point** (e.g. always call `Get-<Name>ModuleDefinition`) instead of an explicit `EntryPoint` field: rejected as unnecessary magic — an explicit field is one line and removes any ambiguity about what gets called.

## Consequences
Adding a new workstation module (Steam, Epic, Windows Configuration, AI tooling, etc.) becomes purely additive: drop a folder with `module.json` + a `.psm1`/`.psd1` pair under `modules/`, implement the lifecycle contract, and it is discovered and run automatically. `Bootstrap.ps1` requires no further changes for the lifetime of the project. Missing dependencies, dependency cycles, and malformed manifests fail loudly at startup with a clear, named error rather than silently skipping a module or crashing with a raw exception.
