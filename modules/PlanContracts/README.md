# Plan Contracts

PHX-005A adds the PlanContracts module as an operator-invoked contract layer. It is intentionally not a module.json orchestration module and performs no installation, configuration mutation, execution, or rollback.

## Contract versions

- Deployment plan: SchemaVersion = 1.0
- Approval record: SchemaVersion = 1.0
- Digest: SHA256

The plan binds a GUID, UTC creation time, Phoenix version/source revision, machine ID and computer name, scope, configuration/manifest/state SHA-256 fingerprints, ordered actions, summary and digest.

Every action requires a stable ActionId, supported category/action, name, exact ManifestIdentity, JSON-compatible Parameters, reason, risk, non-negative order and dependency IDs. Unknown categories/actions, missing manifest identity, duplicate IDs and invalid dependency references are rejected. Array order is preserved. Object keys are sorted using ordinal comparison. No plan field is excluded from the digest except the digest field itself.

## Usage

Create a contract from complete, verified provenance:

~~~powershell
Import-Module .\modules\PlanContracts\PlanContracts.psd1 -Force

$planArgs = @{
    Machine = @{ MachineId = 'machine-guid-or-managed-id'; ComputerName = $env:COMPUTERNAME }
    Scope = 'Profile: Gaming'
    PhoenixVersion = '0.9.0'
    SourceRevision = '<git-commit>'
    ConfigurationFingerprint = '<64-hex-sha256>'
    ManifestFingerprint = '<64-hex-sha256>'
    StateFingerprint = '<64-hex-sha256>'
    Actions = @()
    Summary = @{ Install = 0; Apply = 0; Skip = 0; Defer = 0; Risk = 'Low' }
}
$plan = New-PhoenixDeploymentPlanContract @planArgs
Assert-PhoenixDeploymentPlanContract -Plan $plan
$plan | ConvertTo-Json -Depth 30 | Set-Content .\plans\deployment-plan.json -Encoding utf8
~~~

Create an approval record in an interactive Windows PowerShell 7 ConsoleHost:

~~~powershell
New-PhoenixApprovalRecord -Plan $plan -ApprovalPath .\plans\deployment-plan.approval.json
~~~

The operator must type the exact word APPROVE. Approval validity defaults to four hours and is limited to 1–24 hours. The record includes the current Windows account name and SID and is bound to the plan digest, plan ID, machine, scope, configuration/manifest fingerprints and Phoenix/schema versions.

Validate both artefacts before any later execution integration:

~~~powershell
$approval = Get-Content .\plans\deployment-plan.approval.json -Raw | ConvertFrom-Json
Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval
~~~

## Canonicalisation

Canonical JSON uses compact JSON, ordinally sorted object keys, preserved array order, invariant JSON primitive values, and UTC ISO 8601 for date/time values. UTF-8 without a byte-order mark is hashed with SHA-256. The digest is lowercase hexadecimal. All execution-relevant fields participate.

## Security boundary

The digest detects plan-content changes when the approval record remains unchanged. It is not a digital signature and does not defend against a local administrator who can replace both the plan and approval artefacts or execute modified code. ACL hardening and certificate-backed signatures are future defence-in-depth. Human approval is interactive and tied to the current Windows identity. Non-interactive sessions fail closed. AI recommendations, file existence and command-line flags do not create approval.

## Deliberate limitations

The existing Deployment Planner output is not modified by PHX-005A. It currently lacks several required provenance/action identity fields. A later integration slice must derive and verify those values from actual manifests/configuration/state before wrapping planner output. This module does not invent them.

Autonomous maintenance is not implemented or enabled.
