# 0007 — Application Deployment Engine (Manifest-Driven Installer)

## Status
Accepted

## Context
Roadmap 0.6 needed an Application Installer. The obvious approach — one `Install-Steam.ps1`, one `Install-Git.ps1`, etc. — doesn't scale: supporting 200 applications would mean 200 near-identical scripts, and every one would need its own detection, retry, and logging logic duplicated by hand.

## Decision
Build a generic **Application Deployment Engine** (`modules/Installer`) where every application is data, not code:

- Each application is a JSON manifest under `modules/Installer/Applications/` (`Name`, `Installer` backend, `Id`/`Source`, `ConfigFlag`, `Validate` probes, `Dependencies`, `RunOrder`). Adding an application requires no PowerShell changes.
- Three backends — WinGet, MSI, EXE — each a thin, mockable wrapper around the actual install invocation (`Invoke-PhoenixWinGet`, `Invoke-PhoenixMsiExec`, `Invoke-PhoenixExeInstaller`).
- `Install-PhoenixApplication` is idempotent: it checks whether the app already satisfies its `Validate` probes before attempting installation (per the MANIFESTO's "Idempotent Design" principle), retries on failure, and re-validates after every attempt.
- `ConfigFlag` is a dot-path (e.g. `applications.InstallGit`) checked against the existing merged Phoenix configuration (`Get-PhoenixConfiguration`) — reuses the configuration system that already exists rather than inventing a second one.
- Application dependency ordering reuses `Resolve-PhoenixModuleOrder` from `modules/PhoenixBootstrap` directly. That function is already generic over any object exposing `Name`/`Dependencies`/`RunOrder`; nothing about it is specific to orchestrated *modules*, so writing a second topological sort for *applications* would be pure duplication.
- Validation probes (`Command`, `AppxPackage`, `Path`, `WinGetPackage`) are implemented as new functions in `modules/Validation`, not `modules/Installer` — that module already owns every "is X present on this system" check; `Installer` imports and calls them rather than duplicating detection logic. This is the concrete mechanism behind EPIC-04's "once installers exist, validation can check them automatically."

## Alternatives Considered
- **One script per application**: rejected — the reason this ADR exists.
- **`modules/Installer/Public/` + `Private/` folder-of-files layout** (as originally proposed): rejected in favour of the single-`.psm1`-per-module convention every other module already uses (`PhoenixCore`, `PhoenixBootstrap`, `Validation`). Splitting into many files is a reasonable pattern in general, but introducing a second module-authoring convention here wasn't justified by the amount of code, and consistency was judged more valuable.
- **Bare-string `Validate` arrays** (e.g. `["EpicGamesLauncher.exe"]`, as originally proposed): rejected — a bare name doesn't say whether to check PATH, a Store package, a file path, or a WinGet listing, and guessing would violate the "never assume" standard. Replaced with typed probes (`{"Type": "Command", "Value": "git"}`).
- **`DependsOn` as the manifest field name** (as originally proposed): renamed to `Dependencies` to match `module.json`'s existing field name for the same concept, and to allow direct reuse of `Resolve-PhoenixModuleOrder` without a translation step.
- **Naming-convention-based config gating** (e.g. assume `Install<Name>` exists in some config file): rejected in favour of an explicit `ConfigFlag` dot-path per manifest — explicit is safer than guessed, and some applications (7-Zip) didn't have an existing config flag at all; adding one explicitly was preferable to inventing a naming convention that would have to special-case that gap anyway.
- **A generic system-wide validation report also listing Steam/Epic/etc.**: deferred — see [EPIC-04](../roadmap/EPIC-04-System-Validation.md). `Invoke-PhoenixValidationReport` stays generic; per-application checks live inside `Install-PhoenixApplication`'s own pre/post-install verification, not bolted onto the system-wide report.

## Consequences
Adding a new application is purely additive: write a manifest, no PowerShell changes. The engine is fully testable without ever running a real installer — every backend wraps its actual process invocation in a one-line function that Pester mocks directly. `Test-PhoenixGpu`'s "never assume a hardware vendor" principle and the "never assume a Store package exists" principle from [CONTRIBUTING.md](../../CONTRIBUTING.md#validation-first) both carry through: `Test-PhoenixWinGetPackageInstalled` and `Test-PhoenixAppxPackageAvailable` report absence as informational, and `Install-PhoenixApplication` treats "not yet satisfied" strictly (any probe below PASS) when deciding whether to (re)install, while the system-wide report keeps its more lenient WARN semantics for describing overall system state.
