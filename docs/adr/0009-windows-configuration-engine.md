# 0009 — Windows Configuration Engine (Data-Driven Settings)

## Status
Accepted

## Context
Through v0.7.0 Phoenix can discover, orchestrate, install, validate, and apply workstation profiles — but it cannot configure Windows itself. `configs/windows.json` has carried flags (`ShowFileExtensions`, `DarkMode`, `DisableTelemetry`) since Sprint 0 that nothing reads. Roadmap 0.8 closes that gap.

## Decision
A new `modules/WindowsConfig` module applies Windows settings the same way `modules/Installer` installs applications: every setting is a JSON manifest, not code.

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

- Manifests live in `modules/WindowsConfig/Settings/` — mirroring `modules/Installer/Applications/`. The established split holds: `configs/*.json` states **what the user wants** (flags); module data files state **how Phoenix achieves it** (mechanism).
- Each setting is gated by a `ConfigFlag` dot-path against the merged configuration, exactly like application manifests.
- `Set-PhoenixSetting` is idempotent: it reads the current value first and skips (logging `PASS`) if the desired state already holds. When it does apply, it logs the previous value (rollback data) and re-reads to verify. Results use the same `{Category, Name, Status, Message}` shape as everything else.
- The first supported `Type` is `Registry`, restricted in practice to `HKCU` — safe to apply without elevation. The registry read/write is wrapped in two one-line mockable functions (`Get-PhoenixRegistryValue`, `Set-PhoenixRegistryValue`), so no test ever touches the real registry.
- Orchestrated via `module.json` at `RunOrder: 40` — configure the OS before installing applications (Installer runs at 50, Validation at 90).

### `Get-PhoenixConfigValue` moves to `modules/PhoenixConfig`
The dot-path config resolver was born inside `modules/Installer`, but it is a configuration concern, and `WindowsConfig` needs it too. Duplicating it would violate the repository's own reuse standard, so it moves to its canonical home in `PhoenixConfig`; `Installer` now imports `PhoenixConfig` at module load instead of defining its own copy.

## Alternatives Considered
- **Encoding mechanism into `configs/windows.json`** (registry paths etc. in the user-preference file): rejected — it would collapse the what/how split that keeps user preferences readable and mechanism reviewable.
- **`Invoke-PhoenixConfiguration <Profile>` verb** (from the original proposal): deferred. "Configuration" collides with the existing `Get-PhoenixConfiguration` engine vocabulary, and profile-driven settings deserve their own design pass once settings coverage is broader.
- **PowerShell DSC**: rejected for now — a heavyweight dependency with its own agent/LCM model, poor fit for a lightweight, transparent, per-run engine. The manifest format doesn't preclude a DSC-backed `Type` later.
- **Shipping HKLM settings now** (telemetry policy, Windows Features, services): deferred. They require elevation; applying them without an elevation strategy would either fail confusingly or push users toward running everything as admin. A future ADR covers elevation handling; the `Type` field is the extension point.

## Consequences
`configs/windows.json`'s flags finally do something: `ShowFileExtensions` and `DarkMode` apply real registry state (plus a new `ShowHiddenFiles` flag). Adding a new HKCU setting is one JSON file. `DisableTelemetry` remains declared-but-inert until elevation handling lands — documented in the module README rather than silently half-implemented. Settings that Explorer only picks up on restart are logged as applied; a future enhancement may offer an optional Explorer restart.
