# DeploymentPlanner

The Intelligent Deployment Planner (ADR [0016](../../docs/adr/0016-deployment-planner.md)) — the orchestration "brain." Before Phoenix changes anything, it builds an **explainable plan**: here is exactly what I will do, and why.

```powershell
$plan = New-PhoenixDeploymentPlan -RootPath (Get-Location) -ProfileName Gaming
Show-PhoenixDeploymentPlan -Plan $plan
Export-PhoenixDeploymentPlan -Plan $plan -RootPath (Get-Location)

# or, review the default (configuration-scoped) run without executing:
.\Bootstrap.ps1 -Plan
```

## What it plans

Only **real actions** — Phoenix never plans capabilities it doesn't have.

- **Applications** — selected by a profile (`-ProfileName`, expanded with dependencies) or by configuration (`ConfigFlag`).
- **Settings** — selected by configuration.

Current-vs-desired state and scoping come from the **State Engine** (`Get-PhoenixState`, ADR [0018](../../docs/adr/0018-desired-state-drift-management.md)) — the single source of truth. The planner adds only the deploy-time decisions the State Engine does not own: deferral, ordering, estimates, and risk. The plan still matches a real run:

| Category | Action | When |
|---|---|---|
| Application | `Skip` | already installed |
| Application | `Defer` | preflight unsafe (the Installer would refuse) |
| Application | `Install` | not installed |
| Setting | `Skip` | already in the desired state |
| Setting | `Defer` | requires elevation, process not elevated |
| Setting | `Apply` | not in the desired state |

The plan header reports the detected hardware (`Get-PhoenixHardware`) so plans are machine-aware and auditable.

> An application the State Engine reports as **`Outdated`** still plans as `Skip` — an orchestrated run genuinely skips an installed application and never upgrades. Planning an "Upgrade" would break the promise that the plan matches a real run; upgrades belong to `Invoke-PhoenixRepair`. Because the planner treats `Outdated` and `Present` alike, it asks for state with `-SkipVersionCheck`, avoiding a per-package WinGet query that costs minutes and could not change the plan.

## Honest estimates

`EstimatedSeconds` and `Risk` are **coarse, declared heuristics**, not measurements — a fixed per-action-type estimate and a simple risk rule (machine-scope/elevation changes → `Medium`). Real duration/risk modelling is future work; the fields exist so refining them changes no other module.

## Functions

- `New-PhoenixDeploymentPlan -RootPath [-ProfileName]` — build the plan object.
- `Show-PhoenixDeploymentPlan -Plan` — console rendering for review.
- `Export-PhoenixDeploymentPlan -Plan -RootPath` — persist as timestamped JSON under `plans/` (gitignored, like `reports/`).
- `Get-PhoenixDeploymentPlan -RootPath [-Path]` — load the most recent exported plan.

## Not orchestrated

The planner is a consumer at the top of the dependency graph — nothing depends on it — so it carries no `module.json` and is not an execution stage. `Bootstrap.ps1 -Plan` builds/shows/exports a plan and **exits without executing** (review before deploy). Making execution *consult* the plan (execute-the-plan-not-the-profile) is deferred to pair with Automatic Transactional Rollback (ADR 0015).
