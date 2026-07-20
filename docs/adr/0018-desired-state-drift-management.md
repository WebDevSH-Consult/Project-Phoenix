# 0018 — Desired State & Drift Management Engine (PHX-004)

## Status
Accepted

## Context
Phoenix deploys well; it does not yet *maintain*. Once a machine is provisioned, nothing tracks whether it still matches what Phoenix declared. Three months later a user may have uninstalled Git, changed a registry value, or let an application fall behind — and Phoenix has no idea. Every mature configuration-management system (Microsoft DSC, Puppet, Chef, Ansible, SaltStack) crosses exactly this line: from *provisioning* to *configuration management*. This is the next foundational leap for Phoenix, and — unlike incremental validation slices — it becomes the single source of truth every later feature (compliance reports, scheduled health checks, automatic remediation, golden-workstation comparison, fleet reporting) can build on instead of each re-implementing its own comparison.

The building blocks already exist and must be **reused, not duplicated**:
- Current-state checks: `Test-PhoenixApplicationSatisfied` (installed?), `Test-PhoenixSettingApplied` (registry value matches desired?), and winget's own upgrade detection (`Update-PhoenixApplication` already performs `winget upgrade`).
- Idempotent apply: `Set-PhoenixSetting`, `Install-PhoenixApplication`, `Update-PhoenixApplication` — each already checks desired state first and verifies after.
- The Deployment Planner (ADR [0016](0016-deployment-planner.md)) already computes current-vs-desired *per item*, but inline and only at deploy time; the Recovery engine (ADR [0015](0015-recovery-rollback-engine.md)/[0017](0017-automatic-transactional-rollback.md)) reverses recorded changes, but from a report, not from live drift. Neither answers, on demand, "has this machine drifted from its declaration, and what exactly changed?"

## Decision
A new module, `modules/StateEngine`, becomes Phoenix's single source of truth for **current state vs desired state**, and the basis for auditing and repairing drift.

### Desired state = the manifests in scope
Like DSC/Puppet/Chef, the **declared manifests** (applications and settings selected by configuration or a profile) *are* the desired state. There is no new persisted store on day one. A captured "golden snapshot" store — for golden-workstation comparison and point-in-time compliance — is a future capability that slots in behind the same functions without redesign.

### Honest drift scope — only what Phoenix actually manages
Drift is reported and repaired **only** over capabilities Phoenix genuinely has, on the same discipline that kept the Planner trustworthy (ADR 0016 refused to fabricate driver/optimisation actions):

| Domain | Drift detected | Repairable? | Source |
|---|---|---|---|
| Application presence | `Missing` (declared, not installed) | Reinstall | `Test-PhoenixApplicationSatisfied` |
| Application version | `Outdated` (newer available) | Upgrade | winget upgrade (`Update-PhoenixApplication`) |
| Registry setting | `Modified` (value ≠ desired) | Re-apply | `Test-PhoenixSettingApplied` |

Explicitly **out of scope until their manifest capabilities exist** (reporting them would be fabricated): GPU/driver currency (Phoenix has no driver install or version capability), Windows services and features (WindowsConfig is registry-only; services/features are a deferred manifest `Type`). The moment those capabilities land, the State Engine gains their drift domain for free, because it composes existing checks rather than hard-coding a fixed audit.

### Functions
- **`Get-PhoenixState -RootPath [-ProfileName]`** — the current-state model: for every in-scope application and setting, its live status (`Present`/`Missing`, `Applied`/`Modified`, `UpToDate`/`Outdated`), assembled by calling the existing predicates. Read-only.
- **`Compare-PhoenixState`** — given the current state and the declared desired state, return the **drift set**: only the items where current ≠ desired, each tagged with a drift type (`Missing`, `Modified`, `Outdated`) and the manifest needed to repair it. Reuses the predicates; reimplements no check.
- **`Invoke-PhoenixAudit -RootPath [-ProfileName]`** — run `Get` + `Compare`, render a human-readable drift summary and a JSON artifact (the "here is exactly what has drifted" report). **Changes nothing.**
- **`Invoke-PhoenixRepair -RootPath [-ProfileName] [-DryRun] [-Transactional] [-SkipPreflight]`** — repair **only** the drifted items, by re-applying desired state through the existing idempotent apply/install/upgrade functions. Never a full profile redeploy; never touches what is already correct; verified like any install.

  Two details settled during implementation:
  - The preview switch is **`-DryRun`**, not `-WhatIf`, to match the convention already established on `Install-PhoenixApplication` / `Install-PhoenixApplications` / `Invoke-PhoenixProfile`. Because `Set-PhoenixSetting` and `Update-PhoenixApplication` carry no dry-run of their own, the preview is implemented in the repair loop itself: it reports what it *would* do and invokes no backend.
  - The **preflight gate (ADR 0012) applies to application repairs only** — nothing installs on a non-idle servicing state — while setting repairs proceed, since a registry write is not an installation. `-SkipPreflight` is the same explicit escape hatch the Installer offers. Elevation is handled inside `Set-PhoenixSetting` (WARN-skip, ADR 0013).

  With `-Transactional`, a failed repair reverses the repairs that changed, via `Invoke-PhoenixRollbackFromResults` (ADR 0017) — the repair results are already in the shape the rollback engine consumes. **A version repair is deliberately not reversible**: `Update-PhoenixApplication` reports no `Changed` flag, so the rollback plan skips it. Undoing an upgrade by uninstalling would destroy an application that was legitimately installed before the repair — an honest non-capability rather than a destructive one.

### Reuse constraints (to prevent a parallel system)
1. The State Engine **orchestrates existing predicates** into a state model; it must not duplicate check logic.
2. `Invoke-PhoenixRepair` **reuses the mutating functions** (`Set-PhoenixSetting`, `Install-PhoenixApplication`, `Update-PhoenixApplication`); it adds *selection* (only-drifted) and *ordering*, not new mutation logic.
3. The Planner (ADR 0016) will be refactored to **consume `Compare-PhoenixState`** as its current-vs-desired source instead of calling predicates inline — as a *separate* slice. Because both use the same predicates today, there is no behavioural divergence in the interim; the refactor is a dedupe, not a semantics change.
4. Audit reporting reuses the Dashboard report conventions (ADR 0010) where practical.

### Architecture position
Detect (Hardware) → Validate → **State Engine** → Planner → Execute → Dashboard → Recovery. The State Engine is **operator-invoked** for audit and repair (like Recovery) — it is the *maintain* path, not a stage of a forward deploy — so it carries no `module.json` initially. It is designed to be schedulable later (scheduled health checks / compliance runs) without change.

### Delivery in slices
1. **Slice 1** — `modules/StateEngine` with `Get-PhoenixState`, `Compare-PhoenixState`, `Invoke-PhoenixAudit` (read-only drift detection + report) over the three honest domains, with tests. *Phoenix now knows.*
2. **Slice 2** — `Invoke-PhoenixRepair` (repair only drift via idempotent apply, preflight-gated, `-Transactional`-aware). *Phoenix now maintains.*
3. **Slice 3** — refactor the Deployment Planner to consume the State Engine, making it the single source of truth.

## Alternatives Considered
- **Advanced validation slices first**: valuable but incremental — improvements to an existing module. The State Engine is foundational and subsumes much of "validation as drift"; it should come first so later features share one comparison.
- **A persisted desired-state / golden-snapshot store now**: deferred. The manifests already declare desired state; a snapshot store is a future capability (golden comparison, point-in-time compliance) that fits behind the same functions.
- **Fabricating driver/service drift to match an illustrative audit**: rejected — the same honesty rule as ADR 0016. A drift report that lists things Phoenix cannot actually detect or repair is worse than an honest, narrower one.
- **Extending the Validation module instead of a new module**: rejected. Drift + repair (current-vs-desired producing a repair plan) is a distinct concern, though it consumes Validation's primitives.
- **Repair as a scoped profile redeploy**: rejected — it would reinstall/re-apply things that are already correct. Repair must touch *only* drift.

## Consequences
Phoenix crosses from provisioning into configuration management, Windows-first and PowerShell-native. Because current state, drift, audit, and repair all flow through one module that reuses the existing predicates and idempotent apply paths, later capabilities — scheduled health checks, compliance reports, automatic remediation, configuration snapshots, golden-workstation comparison, fleet reporting — extend this without redesign and without each inventing its own comparison. The honest scope keeps every drift report trustworthy: Phoenix reports exactly what it can detect and repairs exactly what it can fix.
