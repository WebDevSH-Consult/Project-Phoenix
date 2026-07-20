# 0016 — Intelligent Deployment Planner

## Status
Accepted

## Context
Phoenix's pipeline detects, validates, configures, installs, verifies, reports, and recovers — but it executes a profile or configuration *literally*. The one missing element is **decision-making made visible**: before changing anything, produce an explainable plan — "here is exactly what I will do, and why" — that an operator can review, and that is repeatable, auditable, and exportable. This is the orchestration/brain layer over everything already built, and a natural foundation for a future review-before-deploy GUI.

## Decision
A new module, `modules/DeploymentPlanner`, builds a **deployment plan** from the machine's actual state and the work Phoenix can actually perform — no execution.

### Honest scope — plans only real actions
The planner consumes capabilities Phoenix already has and plans **only** over them:

- **Applications**: the manifests under `modules/Installer/Applications` selected either by a **profile** (`-ProfileName`, expanded with dependencies) or by **configuration** (`ConfigFlag`).
- **Settings**: the manifests under `modules/WindowsConfig/Settings` selected by configuration.

It deliberately does **not** invent capabilities Phoenix lacks (driver installs, CPU-vendor "optimisations", applications with no manifest). The plan header reports the detected hardware (`Get-PhoenixHardware`) so the plan is machine-aware and auditable; hardware-*conditional action selection* becomes available for free the day a manifest declares a hardware condition, because the planner already has the hardware object — but no such condition is fabricated now.

### Per-action decision
Each candidate becomes a plan action `{ Category, Name, Action, Reason, Risk, EstimatedSeconds }`:

- **Application** — `Skip` if already satisfied ("already installed"); `Defer` if preflight is unsafe ("system not in a safe state: <reason>", since the Installer would refuse); otherwise `Install` ("not installed").
- **Setting** — `Skip` if already in the desired state; `Defer` if it requires elevation and the process isn't elevated ("requires elevation"); otherwise `Apply` ("not in desired state").

This reuses the exact predicates the executors use (`Test-PhoenixApplicationSatisfied`, `Test-PhoenixSettingApplied`, `Get-PhoenixPreflightState`, `Test-PhoenixElevated`), so the plan matches what a real run would do.

> **Amended by ADR [0018](0018-desired-state-drift-management.md) (slice 3).** Current-vs-desired state and scoping now come from the State Engine's `Get-PhoenixState` rather than the planner calling those first two predicates and loading/scoping manifests itself. The planner keeps the deploy-time decisions the State Engine does not own — deferral for unsafe preflight or missing elevation, ordering, estimates, risk. This is a **dedupe, not a semantics change**: the rendered plan is byte-identical before and after.
>
> Two fidelity points follow from it. An application the State Engine reports as `Outdated` still plans as **`Skip` ("already installed")**, because an orchestrated run genuinely skips an installed application and never upgrades — upgrades belong to `Invoke-PhoenixRepair` (ADR 0018), and a plan claiming "Upgrade" would stop matching a real run. And because the planner treats `Outdated` and `Present` identically, it requests state with `-SkipVersionCheck`, avoiding a per-package WinGet query that costs minutes and could not change the plan.

### Estimates and risk are honest coarse heuristics
`EstimatedSeconds` and `Risk` are **declared placeholders**, not measurements: a fixed per-action-type estimate (install ≈ 120 s, setting apply ≈ 5 s, skip/defer = 0) and a simple risk rule (machine-scope/elevation-requiring applies → `Medium`, else `Low`). The plan and this ADR both mark them as rough. Real duration/bandwidth/disk/risk modelling is future work (the proposal lists them under "future expansion"); the framework carries the fields so refining them later changes no other module.

### Functions
- `New-PhoenixDeploymentPlan -RootPath [-ProfileName]` — build the plan object.
- `Show-PhoenixDeploymentPlan -Plan` — human-readable console rendering ("Install Discord — not installed (~2m, Low)").
- `Export-PhoenixDeploymentPlan -Plan -RootPath` — persist the plan as timestamped JSON under `plans/` (gitignored, like `reports/`) — the auditable, exportable artifact.
- `Get-PhoenixDeploymentPlan -RootPath [-Path]` — load the most recent exported plan (symmetry with the report/recovery loaders).

### Bootstrap integration — non-invasive
`Bootstrap.ps1 -Plan` builds a configuration-scoped plan, shows it, exports it, and **exits without executing** — "review before deploy," with no change to the orchestrated execution path. Wiring the plan as a hard gate that the executors consult (execute-the-plan-not-the-profile) is deferred: it would reshape each module's Execute stage, and belongs with the Automatic Transactional Rollback work that follows (ADR 0015). The planner is a consumer at the top of the dependency graph — nothing depends on it — so it carries no `module.json` and is not an orchestrated stage.

## Alternatives Considered
- **Plan with fabricated hardware-conditional actions** (AMD driver, Ryzen tweaks) to match the illustrative proposal: rejected — the plan must be trustworthy. A plan that lists actions the engine can't perform is worse than no plan. Those arrive automatically when their manifests do.
- **Precise time/risk estimates now**: rejected as fabricated precision — coarse, clearly-labelled heuristics are honest; a real model is future work.
- **Making Bootstrap execute the plan object instead of running modules directly**: deferred — a larger orchestration change, naturally paired with transactional rollback, and not needed to deliver the reviewable-plan value now.

## Consequences
Every deployment becomes explainable, repeatable, auditable, exportable, and reviewable before execution — Phoenix reads like an enterprise provisioning platform rather than a script. Because the plan header already carries the hardware object and the action list uses the real executor predicates, later refinements (hardware-conditional manifests, better estimates, plan-gated execution, a GUI review step) extend this module without touching the ones beneath it.
