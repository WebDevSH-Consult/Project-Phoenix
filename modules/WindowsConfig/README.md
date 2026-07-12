# WindowsConfig

The Windows Configuration Engine (Roadmap 0.8). Every Windows setting is a JSON manifest under [`Settings/`](./Settings/) — adding a setting requires no PowerShell changes, mirroring the [Installer](../Installer/README.md)'s manifest-driven design. See [ADR 0009](../../docs/adr/0009-windows-configuration-engine.md).

Orchestrated automatically via `module.json` at `RunOrder: 40` — the OS is configured before applications install (Installer runs at 50, Validation at 90).

## Setting manifest schema

```json
{
  "Name": "Show file extensions",
  "Type": "Registry",
  "ConfigFlag": "windows.ShowFileExtensions",
  "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
  "ValueName": "HideFileExt",
  "DesiredValue": 0,
  "ValueKind": "DWord"
}
```

| Field | Meaning |
|---|---|
| `Name` | Unique display name. |
| `Type` | Mechanism. `Registry` is the only type today; the field is the extension point for Windows Features, services, power plans, etc. |
| `ConfigFlag` | Dot-path into the merged configuration (e.g. `windows.DarkMode`, matching `configs/windows.json`) gating whether the setting applies. A missing flag means **not enabled** — never assumed. |
| `Path` / `ValueName` / `DesiredValue` / `ValueKind` | Registry-type specifics: where, which value, what it should be, and its registry kind (`DWord`, `String`, ...). |
| `RequiresElevation` | Optional, default `false`. Machine-scope settings (HKLM) set this; without rights they skip with `WARN` instead of failing (ADR [0013](../../docs/adr/0013-elevation-strategy.md)). |

## Apply flow

`Set-PhoenixSetting`, per setting:

1. **Read first.** If the current value already matches `DesiredValue`, log success and return — nothing written (idempotent). Reads work without elevation, so this applies to machine-scope settings too.
2. **Elevation gate** (ADR [0013](../../docs/adr/0013-elevation-strategy.md)): if the manifest declares `RequiresElevation: true`, a change is needed, and the process isn't elevated → skip with `WARN` ("re-run elevated to apply"), never attempt-and-fail. Phoenix does not auto-elevate.
3. **Record the previous value** in the log and in the result's `PreviousValue` property — the rollback data for a future repair capability.
4. **Apply** via `Set-PhoenixRegistryValue` (creates the key if missing).
5. **Re-read to verify.** A write that doesn't stick is `FAIL`, not assumed success.

Results are `{ Category: 'Setting', Name, Status, Message, PreviousValue, Changed }` — the same vocabulary as installer and validation results. `Changed` is `$true` only on a verified apply (`$false` for already-desired, elevation-skip, and failure); it's the signal the [Recovery engine](../Recovery/README.md) filters on to roll back only confirmed changes, and `PreviousValue` is the rollback data. `Remove-PhoenixRegistryValue` is exported for Recovery to remove a value Phoenix introduced.

## Scope and limitations (deliberate)

- **Machine-scope (HKLM) settings require an elevated run.** `Bootstrap.ps1` states at startup whether it's elevated; non-elevated runs skip `RequiresElevation` settings with a clear `WARN` in the log and report. See ADR 0013.
- **Explorer-read settings apply at next Explorer restart** (or sign-out/in). Phoenix logs the setting as applied and verified at the registry level; it does not restart Explorer for you.
- **The registry provider is two one-line mockable functions** (`Get-PhoenixRegistryValue` / `Set-PhoenixRegistryValue`) — no test ever touches the real registry.
- **Windows Features and services** are still future work — ADR 0013 settles *how* elevation is handled; those capabilities come as new manifest `Type`s.

## Shipped settings

| Setting | Flag | Effect | Elevation |
|---|---|---|---|
| Show file extensions | `windows.ShowFileExtensions` | `HideFileExt = 0` | — |
| Show hidden files | `windows.ShowHiddenFiles` | `Hidden = 1` | — |
| Dark mode (apps) | `windows.DarkMode` | `AppsUseLightTheme = 0` | — |
| Dark mode (system) | `windows.DarkMode` | `SystemUsesLightTheme = 0` | — |
| Minimize diagnostic data | `windows.DisableTelemetry` | `AllowTelemetry = 1` (policy) | required |

Note on telemetry: `AllowTelemetry = 1` (Required diagnostic data only) is the effective minimum on Windows Pro; `0` (Security tier) applies only to Enterprise/Education and silently falls back elsewhere — Phoenix sets the value that actually works rather than the one that merely looks stricter.
