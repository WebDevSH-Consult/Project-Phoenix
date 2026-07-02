# 0008 — Workstation Profiles

## Status
Accepted

## Context
With the Application Deployment Engine (ADR 0007) in place, installing applications is manifest-driven — but selecting *which* applications still means editing per-flag booleans in `configs/*.json`. The VISION's "Workstation DNA" concept calls for something higher-level: describe the workstation you want ("Gaming", "Development") and let Phoenix determine the applications.

## Decision
A profile is a JSON file under `profiles/` at the repository root:

```json
{
  "Name": "Gaming",
  "Description": "Game launchers and supporting tools.",
  "Applications": ["Steam", "Epic Games Launcher", "7-Zip"]
}
```

`Invoke-PhoenixProfile -ProfileName Gaming` loads the profile, expands its application list to include transitive dependencies (from the application manifests' own `Dependencies`), orders the result with `Resolve-PhoenixModuleOrder`, and installs each via the existing `Install-PhoenixApplication` — inheriting its idempotency, retry, and validation behaviour unchanged.

Key semantics:

- **A profile is an explicit selection.** It installs exactly what it lists (plus dependencies), regardless of `ConfigFlag` values. `ConfigFlag` gating remains the mechanism for the default orchestrated run (`Bootstrap.ps1` → Installer module); profiles are the mechanism for deliberate, named deployments. Two different questions — "what does this workstation get by default?" versus "make this a gaming machine" — get two different mechanisms.
- **JSON, not YAML** (as originally proposed). Every configuration artifact in this repository is JSON, validated by the existing CI job, parsed by built-in `ConvertFrom-Json`. YAML would add a third-party parser dependency and a second configuration syntax for no capability gain.
- **Profiles live in `modules/Installer` for now**, not a new module. Today a profile selects applications only — it is a thin composition layer over `Install-PhoenixApplications`. If profiles later select Windows tweaks, AI configuration, etc., the capability can graduate to its own module; building that generality now would be speculative.
- **Profiles may only reference applications that have manifests.** An unknown name fails loudly at expansion time. The shipped profiles (Gaming, Development) reference only the six manifests that exist — no aspirational entries for applications Phoenix can't install yet.

## Alternatives Considered
- **YAML profiles**: rejected — see above.
- **Profiles override/set ConfigFlags** (profile as a config layer): rejected. It would make `Invoke-PhoenixProfile` mutate or shadow configuration state, entangling the two selection mechanisms. Keeping them orthogonal is simpler to reason about and test.
- **A separate `Profiles` module**: rejected as premature — one exported function and a discovery helper don't justify a module boundary yet.

## Consequences
`Invoke-PhoenixProfile Gaming` / `Invoke-PhoenixProfile Development` work end to end today. Adding a new profile is one JSON file; adding a new application to a profile is one line — provided its manifest exists, which is the forcing function ensuring Phoenix can actually install and validate everything a profile promises.
