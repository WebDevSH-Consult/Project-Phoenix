# Plan Freshness

PHX-005B ([spec](../../docs/specs/PHX-005-plan-gated-execution.md), [ADR 0019](../../docs/adr/0019-plan-gated-transactional-execution.md)) adds the freshness gate: before an approved plan may run, Phoenix rebuilds the same plan now and rejects the approved one if anything that matters has changed.

**Read-only.** Nothing in this module installs, applies, executes or rolls back. It is operator-invoked (no `module.json`), so normal orchestration never discovers it.

## What it produces

The PHX-005A plan contract ([PlanContracts](../PlanContracts/README.md)) needs provenance the planner did not provide. This module supplies it:

| Field | Source |
| --- | --- |
| `Machine.MachineId` / `ComputerName` | Windows `MachineGuid` (`HKLM:\SOFTWARE\Microsoft\Cryptography`) and computer name. Fails if either cannot be read. |
| `PhoenixVersion` / `SourceRevision` | `VERSION` file; `git rev-parse HEAD` (empty if git is unavailable). |
| `ConfigurationFingerprint` | SHA-256 of the merged `Get-PhoenixConfiguration` output in canonical JSON. Key order and whitespace do not change it. |
| `ManifestFingerprint` | SHA-256 over every application manifest, setting manifest and profile (path + canonical hash of each). All files, not just those in scope. |
| `StateFingerprint` | SHA-256 over scope, elevation, preflight safety and each in-scope item's category, name and status from the State Engine. Timestamps and hardware detail are excluded. |
| `ActionId` | `<category>:<slug of name>`, e.g. `application:visual-studio-code`. |
| `ManifestIdentity` | `<Category>/<Name>#sha256:<canonical hash of the manifest file>`. |
| `Parameters` | `{ ManifestPath }`, the repository-relative manifest path. |
| `Dependencies` | Application manifest dependencies mapped to action IDs. A dependency outside the plan scope is refused. |

Plan decisions (`Install` / `Apply` / `Skip` / `Defer`, reason, risk, order) come unchanged from `New-PhoenixDeploymentPlan`. `Outdated` applications are still planned as `Skip`.

## Freshness checks

`Test-PhoenixPlanFreshness -Plan <plan> -RootPath <root>` returns a result object with per-check detail. It never throws. `Assert-PhoenixPlanFreshness` throws with the failed checks when the plan is stale.

| Check | Fails when |
| --- | --- |
| `PlanContract` | The plan is malformed, uses an unknown schema or its digest does not match. Nothing is rebuilt. |
| `Scope` | The scope label is not `Configuration` or `Profile: <name>`. |
| `Evaluation` | The current plan cannot be rebuilt (for example, a State Engine error). Unknown freshness is stale. |
| `MachineIdentity` | MachineGuid or computer name differ. |
| `PhoenixVersion` | The Phoenix version differs. |
| `ConfigurationFingerprint` | Any configuration value changed. |
| `ManifestFingerprint` | Any manifest or profile was added, removed or changed. |
| `StateFingerprint` | Any in-scope item's status, elevation or preflight safety changed. |
| `ActionSet` | Any action was added, removed or changed in ID, category, name, action, manifest identity, parameters, dependencies or order. |

Not treated as staleness: timestamps, hardware detail, reworded `Reason` text, `Risk`, and source revision (reported as `SourceRevisionNote` for information).

Elevation and installer preflight are covered twice: both are in the state fingerprint, and losing either changes planner actions to `Defer`. PHX-005C must still recheck installer preflight immediately before each install.

## Usage

~~~powershell
Import-Module .\modules\PhoenixLogging\PhoenixLogging.psd1
Initialize-PhoenixLog -LogDirectory .\logs
Import-Module .\modules\PlanFreshness\PlanFreshness.psd1
Import-Module .\modules\PlanContracts\PlanContracts.psd1

# Build a contract plan for this machine (read-only) and save it.
$plan = New-PhoenixContractPlan -RootPath (Get-Location) -ProfileName 'Development'
[IO.File]::WriteAllText('.\plans\dev.plan.json', (ConvertTo-PhoenixCanonicalJson -InputObject $plan))

# Later, before execution: load with the strict reader and check freshness.
$approved = Read-PhoenixDeploymentPlanContract -Path '.\plans\dev.plan.json'
Assert-PhoenixPlanFreshness -Plan $approved -RootPath (Get-Location)
~~~

Load plans with `Read-PhoenixDeploymentPlanContract`, not `ConvertFrom-Json`: PowerShell converts ISO 8601 strings to `DateTime`, which breaks the digest.

## Limits

- Freshness is a revalidation, not a lock. State can still change between this check and each action; PHX-005C verifies per action.
- Fingerprints are not signatures. A local administrator who can edit the plan, approval and manifests can defeat them (ADR 0019).
- Approval checks stay in PlanContracts (`Assert-PhoenixApprovalRecord`). The PHX-005C executor will run both gates.
