# Installer

The Application Deployment Engine (Roadmap 0.6). Every application is a JSON manifest under [`Applications/`](./Applications/) — adding a new one requires no PowerShell changes. See [ADR 0007](../../docs/adr/0007-application-deployment-engine.md) for the full design rationale.

## Application manifest schema

```json
{
  "Name": "Git",
  "Installer": "Winget",
  "Id": "Git.Git",
  "ConfigFlag": "applications.InstallGit",
  "Validate": [
    { "Type": "Command", "Value": "git" }
  ],
  "Dependencies": [],
  "RunOrder": 100
}
```

| Field | Required | Meaning |
|---|---|---|
| `Name` | yes | Display name, also used for dependency references. |
| `Installer` | yes | `Winget`, `MSI`, or `EXE`. |
| `Id` | for `Winget` | The WinGet package ID. |
| `Source` | for `MSI`/`EXE` | Path to the installer file. |
| `Arguments` | no | Extra arguments passed to the MSI/EXE backend. |
| `ConfigFlag` | yes | Dot-path into the merged Phoenix configuration (e.g. `applications.InstallGit`, matching `configs/applications.json`) that gates whether this application installs at all. A missing flag is treated as **not enabled** — never assumed. |
| `Validate` | yes | Array of typed probes (see below) used both to skip installation when already satisfied (idempotent) and to confirm success afterward. |
| `Dependencies` | no (default `[]`) | Names of other applications that must install first. |
| `RunOrder` | no (default `100`) | Tiebreaker when applications have no dependency relationship to each other. |

## Validate probe types

Each probe is `{ "Type": ..., "Value": ... }`, dispatched to the matching function in [modules/Validation](../Validation/README.md):

| Type | Calls | Use for |
|---|---|---|
| `Command` | `Test-PhoenixCommandAvailable` | Tools that land on PATH (`git`, `code`, `pwsh`). |
| `AppxPackage` | `Test-PhoenixAppxPackageAvailable` | Microsoft Store packages. |
| `Path` | `Test-PhoenixPathExists` | A known, reliable install-location file. |
| `WinGetPackage` | `Test-PhoenixWinGetPackageInstalled` | Anything installed via WinGet without a reliable PATH command or predictable install path (Steam, Epic, 7-Zip). |

Bare filename strings (e.g. `"EpicGamesLauncher.exe"`) are deliberately **not** supported — a bare name doesn't say whether to check PATH, a file path, or a package listing, and guessing would violate the "never assume" standard in [CONTRIBUTING.md](../../CONTRIBUTING.md#validation-first).

## Preflight safety gate (ADR 0012)

Before installing anything, `Install-PhoenixApplications` and `Invoke-PhoenixProfile` run [Validation's installer preflight](../Validation/README.md#installer-preflight-adr-0012): pending reboot, pending file operations, active installer session. On `FAIL` they install **nothing** and return the failing preflight results (which flow into the deployment report with a clear recommended action — usually "restart first"). `-SkipPreflight` is the explicit operator escape hatch. The rule is universal: no system-level installation runs on a non-idle Windows servicing state.

## Install flow

`Install-PhoenixApplication`, per application:

1. **Check first.** If every `Validate` probe already `PASS`es, log success and return — no install attempted (idempotent, per [MANIFESTO.md](../../MANIFESTO.md)'s "Idempotent Design").
2. **Install.** Dispatch to the backend named by `Installer`.
3. **Re-validate.** Every `Validate` probe must `PASS` after the attempt for it to count as success.
4. **Retry.** Up to `MaxAttempts` (default 2) before giving up and returning `FAIL`.

`Install-PhoenixApplications` filters the full manifest set down to whatever's enabled by `ConfigFlag`, orders the result via `Resolve-PhoenixModuleOrder` (reused directly from [PhoenixBootstrap](../PhoenixBootstrap/README.md) — it's already generic over `Name`/`Dependencies`/`RunOrder`), and installs each in order.

Every result is `{ Category: 'Application', Name, Status, Message }` — the same shape [modules/Validation](../Validation/README.md) uses, so installer and validation results compose into one vocabulary.

## Dry-run, upgrade, uninstall (ADR 0014)

| Operation | Function | Behaviour |
|---|---|---|
| **Dry-run** | `-DryRun` on `Install-PhoenixApplication` / `Install-PhoenixApplications` / `Invoke-PhoenixProfile` | Previews the plan, invokes no backend, skips the preflight gate. Already satisfied → `PASS` ("no action would be taken"); change pending → `WARN` ("would install via <backend>"). Surfaces drift without failing the run. |
| **Upgrade** | `Update-PhoenixApplication -Manifest` | WinGet: `winget upgrade`. Not installed → `WARN` (nothing to upgrade); non-WinGet backend → `WARN` (not supported). |
| **Uninstall** | `Uninstall-PhoenixApplication -Manifest` | WinGet (`winget uninstall`) and MSI (`msiexec /x`), each verified gone afterward. Not installed → `PASS` (idempotent); EXE → `WARN` (no standard silent uninstall). |

Upgrade and uninstall are operator-invoked utilities — the orchestrated bootstrap run provisions *toward* a desired state, it doesn't remove things.

## Workstation profiles

A profile is a JSON file under [`profiles/`](../../profiles/) at the repository root — a named, explicit application selection (see [ADR 0008](../../docs/adr/0008-workstation-profiles.md)):

```json
{
  "Name": "Gaming",
  "Description": "Game launchers and supporting tools.",
  "Applications": ["Steam", "Epic Games Launcher", "7-Zip"]
}
```

```powershell
Invoke-PhoenixProfile Gaming
```

`Invoke-PhoenixProfile` expands the list to include transitive dependencies, orders it with `Resolve-PhoenixModuleOrder`, and installs each application via `Install-PhoenixApplication` — inheriting its idempotency, retry, and validation behaviour unchanged.

**A profile bypasses `ConfigFlag` gating.** Config flags answer "what does this workstation get by default?" (the orchestrated `Bootstrap.ps1` run); a profile answers "make this a gaming machine" — an explicit, deliberate selection. The two mechanisms are intentionally orthogonal.

A profile may only reference applications that have manifests — an unknown name fails loudly at expansion time, before anything installs. Shipped profiles: `Gaming`, `Development`.

## Why `module.json` declares no `Dependencies`

`Installer` calls into `Validation`'s exported functions, but that's a **code** dependency (it `Import-Module`s `Validation.psd1` itself, inside its own `Initialize` stage), not an **orchestration** dependency. Declaring `Validation` as a module.json dependency would force Validation's full lifecycle to run *before* Installer's — the opposite of Validation's intended `RunOrder: 90` ("run last, check what was just done"). The two kinds of dependency are different; only the orchestration kind belongs in `module.json`.

## Backends

Each backend wraps its actual process invocation in a one-line function (`Invoke-PhoenixWinGet`, `Invoke-PhoenixMsiExec`, `Invoke-PhoenixExeInstaller`) so Pester can mock exactly that call — no test ever runs a real installer.
