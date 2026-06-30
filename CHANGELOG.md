# Changelog

All notable changes to this project are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/), and versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `modules/PhoenixConfig`: configuration engine (`Get-PhoenixConfiguration`) that loads `phoenix.json` and every per-domain config file it references (`configs/windows.json`, `applications.json`, `gaming.json`, `ai.json`, `powershell.json`) into a single merged object. Missing or malformed config files fail cleanly with a logged `ERROR` entry rather than a raw exception.
- `Bootstrap.ps1` now loads configuration through `Get-PhoenixConfiguration` instead of parsing `phoenix.json` directly.
- Pester tests covering successful merge, missing files, and malformed JSON for both the root and per-domain config files.
- `modules/PhoenixCore`: `Get-PhoenixVersion` reads the `VERSION` file and returns `Version`/`Major`/`Minor`/`Patch`. `Bootstrap.ps1` logs it at startup and exposes a `-Version` switch that prints it and exits without running any modules. Closes [#13](https://github.com/WebDevSH-Consult/Project-Phoenix/issues/13).
- `modules/PhoenixBootstrap`: the Bootstrap Engine (Roadmap 0.5). Discovers every module under `modules/` declaring a `module.json` manifest (`Get-PhoenixModuleManifest`), resolves dependency/run order (`Resolve-PhoenixModuleOrder`), and executes them via the existing `Invoke-PhoenixBootstrap` (`Invoke-PhoenixOrchestration`). `Bootstrap.ps1` now contains no reference to any specific module — adding a new one (Steam, Epic, Windows Configuration, AI tooling, etc.) is purely additive. See ADR [0006](docs/adr/0006-module-manifest-and-orchestration.md).
- `modules/Example` gained a `module.json`, becoming the first orchestrated module discovered automatically rather than hard-coded into `Bootstrap.ps1`.
- Pester tests covering manifest discovery/validation, dependency resolution (ordering, tie-breaking, missing dependencies, cycles), and an end-to-end orchestration run.

## [0.2.0] - Phoenix Core

### Added
- `modules/PhoenixLogging`: structured, leveled logging engine (`Initialize-PhoenixLog`, `Write-PhoenixLog`).
- `modules/PhoenixCore`: module lifecycle dispatcher (`Invoke-PhoenixModuleLifecycle`, `Invoke-PhoenixBootstrap`) implementing Initialise → Validate → Execute → Verify → Log → Report, returning a health object per module.
- `modules/Example`: minimal reference module demonstrating the Phoenix module contract.
- `Bootstrap.ps1`: working entry point that loads `phoenix.json`, imports the logging engine and core, and runs the registered module set through `Invoke-PhoenixBootstrap`.
- Pester test suite under `tests/` covering PhoenixCore, PhoenixLogging, and the Example module.
- CI: new `Module Tests (Pester)` job.

## [0.1.0] - Foundation

### Added
- Repository foundation: full directory structure (`bootstrap/`, `modules/`, `configs/`, `templates/`, `docs/`, `tests/`, `scripts/`, `assets/`, `dashboard/`, `installers/`, `logs/`, `temp/`).
- Branch strategy: `main`, `develop`, and feature branches for all planned modules.
- Core documentation: README, MANIFESTO, ARCHITECTURE, CONTRIBUTING, ROADMAP, SECURITY, CODE_OF_CONDUCT, PROJECT_CHARTER.
- Architectural Decision Record framework under `docs/adr/`.
- GitHub project scaffolding: issue templates, PR template, CODEOWNERS, CI workflow skeleton.
- MIT License.
