# StateEngine

The Desired State & Drift Management Engine (ADR [0018](../../docs/adr/0018-desired-state-drift-management.md), PHX-004) — the single source of truth for **current state vs desired state**. Phoenix's other engines *deploy*; this one lets Phoenix *maintain*: know when a machine has drifted from what Phoenix declared, and (slice 2) repair only the drift.

```powershell
Invoke-PhoenixAudit  -RootPath (Get-Location)            # what has drifted? (read-only)
Invoke-PhoenixRepair -RootPath (Get-Location) -DryRun    # what would be repaired?
Invoke-PhoenixRepair -RootPath (Get-Location)            # fix only the drift
```

## Desired state = the manifests

Like DSC/Puppet/Chef, the **declared manifests** in scope (config- or profile-selected) *are* the desired state. There is no separate store — a captured golden snapshot is future work. The engine **orchestrates the existing predicates** into a state model; it reimplements no check.

## Honest drift surface

Drift is reported only over what Phoenix genuinely manages:

| Domain | Drift | Detected by |
|---|---|---|
| Application presence | `Missing` — declared, not installed | `Test-PhoenixApplicationSatisfied` |
| Application version | `Outdated` — installed, newer available (WinGet) | `Test-PhoenixApplicationOutdated` |
| Registry setting | `Modified` — value ≠ desired | `Test-PhoenixSettingApplied` |

Drivers and Windows services are **out of scope** until their manifest capabilities exist — Phoenix reports only what it can truly detect (and, later, repair), never fabricated drift.

## Functions

- `Get-PhoenixState -RootPath [-ProfileName]` — the current-state model: every in-scope application (`Missing`/`Outdated`/`Present`) and setting (`Modified`/`Applied`), evaluated against its declaration. Read-only.
- `Compare-PhoenixState -State` — a pure function returning the **drift set**: only non-conforming items, each tagged with a `DriftType` and its manifest (so a repair can act on exactly the drift).
- `Invoke-PhoenixAudit -RootPath [-ProfileName]` — run both, render a summary, and write a timestamped JSON artifact under `audits/` (gitignored, like `reports/` and `plans/`). Changes nothing.
- `Invoke-PhoenixRepair -RootPath [-ProfileName] [-DryRun] [-Transactional] [-SkipPreflight]` — repair **only** the drift.

## Repair

Repair re-applies desired state for the drifted items **and nothing else** — never a profile redeploy, never touching what is already correct. Each fix reuses the module that owns that change, so every repair is idempotent and self-verifying:

| Drift | Repaired by |
|---|---|
| `Missing` | `Install-PhoenixApplication` |
| `Outdated` | `Update-PhoenixApplication` |
| `Modified` | `Set-PhoenixSetting` |

Settings are repaired before applications (forward deployment order). The **preflight gate applies to application repairs only** — nothing installs on a non-idle servicing state — while setting repairs continue, since a registry write is not an installation (`-SkipPreflight` is the escape hatch). Elevation is handled inside `Set-PhoenixSetting` (WARN-skip).

`-DryRun` reports what it *would* repair without invoking any backend. `-Transactional` reverses the repairs that changed if any repair fails, via the Recovery engine (ADR [0017](../../docs/adr/0017-automatic-transactional-rollback.md)).

> A **version repair is deliberately not reversible**. `Update-PhoenixApplication` reports no `Changed` flag, so a rollback skips it — undoing an upgrade by uninstalling would destroy an application that was legitimately installed before the repair. An honest non-capability rather than a destructive one.

## Coming next

- **Slice 3** — the Deployment Planner (ADR 0016) consumes `Compare-PhoenixState`, making the State Engine the single source of truth.

## Not orchestrated

Auditing and repair are the *maintain* path, not a forward-deploy stage — so this module has **no `module.json`**. It is operator-invoked, and designed to be schedulable later (health checks, compliance runs) without change.
