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

## Apply flow

`Set-PhoenixSetting`, per setting:

1. **Read first.** If the current value already matches `DesiredValue`, log success and return — nothing written (idempotent).
2. **Record the previous value** in the log and in the result's `PreviousValue` property — the rollback data for a future repair capability.
3. **Apply** via `Set-PhoenixRegistryValue` (creates the key if missing).
4. **Re-read to verify.** A write that doesn't stick is `FAIL`, not assumed success.

Results are `{ Category: 'Setting', Name, Status, Message, PreviousValue }` — the same vocabulary as installer and validation results.

## Scope and limitations (deliberate)

- **HKCU only for now.** Every shipped setting writes to the current user's hive, which needs no elevation. HKLM settings (telemetry policy, Windows Features, services) are deferred until an elevation strategy is designed — which is why `configs/windows.json`'s `DisableTelemetry` flag remains declared-but-inert. See ADR 0009.
- **Explorer-read settings apply at next Explorer restart** (or sign-out/in). Phoenix logs the setting as applied and verified at the registry level; it does not restart Explorer for you.
- **The registry provider is two one-line mockable functions** (`Get-PhoenixRegistryValue` / `Set-PhoenixRegistryValue`) — no test ever touches the real registry.

## Shipped settings

| Setting | Flag | Effect |
|---|---|---|
| Show file extensions | `windows.ShowFileExtensions` | `HideFileExt = 0` |
| Show hidden files | `windows.ShowHiddenFiles` | `Hidden = 1` |
| Dark mode (apps) | `windows.DarkMode` | `AppsUseLightTheme = 0` |
| Dark mode (system) | `windows.DarkMode` | `SystemUsesLightTheme = 0` |
