# 0019 — Plan-Gated Transactional Execution and Hybrid Authority

## Status
Proposed — architecture approved for implementation on `feature/phx-005-plan-gated-execution`.

## Decision owner
Project Phoenix operator.

## Context
Phoenix v0.9.0 can create an explainable deployment plan (ADR 0016) and can run an opt-in transactional deployment that reverses confirmed changes after an unhealthy module result (ADR 0017). These capabilities are currently separate:

- `Bootstrap.ps1 -Plan` creates, displays, exports, and exits.
- `Bootstrap.ps1 -Transactional` runs normal module orchestration and then rolls back confirmed changes if any module is not Healthy.

The missing production-hardening capability is to execute the exact plan an operator reviewed, as one transaction. The current transactional path also completes orchestration before evaluating health. PHX-005 introduces an explicit plan execution path and fail-fast semantics without changing the default orchestration path.

The operator has selected a **hybrid authority model**:
- Human approval is mandatory for initial workstation builds and major or high-impact changes.
- Phoenix may perform routine maintenance autonomously only inside a narrow, explicit, pre-authorised policy.
- Phoenix must never expand its own authority, convert a denied action into an approved one, or treat an AI recommendation as operator approval.

## Decision

### 1. Plan lifecycle
The plan-gated lifecycle is:

1. **Plan** — build an explainable plan from the State Engine and existing deployment predicates. Planning is read-only.
2. **Review** — display and export the complete plan, including scope, machine context, action list, risk, deferrals, estimates, and provenance.
3. **Approve** — an authorised interactive operator explicitly approves the exact plan. Approval is a separate recorded artefact bound to the plan digest and execution context.
4. **Revalidate** — immediately before execution, verify the plan schema, digest, approval record, expiry, machine identity, configuration/manifests, scope, elevation, preflight and relevant current state.
5. **Execute** — execute only the approved actionable entries, in deterministic dependency/run order, through the existing owning modules and their public functions.
6. **Verify** — verify each action using the owning module's existing verification path and reconcile the final state.
7. **Commit or recover** — commit only if every required action and final verification succeeds. Otherwise stop dispatching further actions and reverse confirmed reversible changes in reverse execution order using the Recovery engine.
8. **Report** — write a deployment report linked to the plan ID, plan digest, approval record, execution results, rollback results, and final transaction outcome.

A plan is immutable after approval. Any content change requires a new plan and new approval.

### 2. Plan and approval integrity
The exported plan receives a schema version, stable plan ID, creation time, Phoenix version and source revision, machine context, configuration/manifest provenance, scope, ordered actions, and a canonical SHA-256 digest.

The approval record binds at minimum:
- Plan ID and canonical plan digest.
- Approver identity from the current Windows security context.
- Approval timestamp and expiry.
- Target machine identity and plan scope.
- Configuration/manifest fingerprint.
- Phoenix version and plan schema version.
- Explicit approval decision.

The approval record is stored separately from the plan. The executor rejects missing, mismatched, expired, malformed, or unsupported approval records. The initial implementation must clearly document its threat model: a local administrator able to alter both plan and approval artefacts is outside the protection offered by a plain digest. File ACL hardening and optional certificate-backed signatures are future defence-in-depth, not claims made by the initial digest mechanism.

Approval must be an affirmative operator action in an interactive session. A command-line switch, unattended process, AI-generated recommendation, file existence, or previous approval must not silently approve a new plan. Non-interactive execution must fail closed unless a separately designed, policy-authorised maintenance grant applies.

### 3. Freshness and drift protection
Approval is valid only for the approved target and context. Before the first mutation, the executor must:
- Recompute a fresh state/plan view for the same scope.
- Compare the actionable set, action parameters, dependencies, and relevant state against the approved plan.
- Recheck configuration and manifest fingerprints.
- Recheck machine identity, elevation, and preflight.
- Reject if a planned action is no longer needed, a new action has appeared, an action changed, the machine/context changed, or required safety conditions are no longer satisfied.

The comparison must ignore non-semantic fields such as display formatting and generated timestamps, but must not ignore any field that changes what will execute. If safe equivalence cannot be proven, reject and require a new plan and approval. Recheck volatile safety conditions such as installer preflight immediately before each application installation.

### 4. Execution boundary
The executor dispatches only supported `Install` and `Apply` actions present in the approved plan. `Skip` and `Defer` entries are recorded but never dispatched. Unknown categories, action names, parameters, manifest references, duplicate action identities, dependency cycles, and unsupported schema versions fail closed.

The executor must reuse existing public operations from Installer and WindowsConfig. It must not reimplement install, registry mutation, elevation, or verification logic. It must not call the normal profile orchestration after approval, because that could execute work outside the approved action set.

Actions execute in deterministic dependency/run order. A failure prevents any later action from starting. A failed or interrupted action whose post-state cannot be established is marked **uncertain** and is not automatically reversed. Recovery reverses only changes positively confirmed as changed, using the existing `Changed` evidence and `Undo-*` primitives. Rollback is best-effort and individually verified; Phoenix must report partial recovery honestly.

### 5. Hybrid authority policy

#### Human approval required
Human approval is mandatory for:
- Initial workstation provisioning/builds.
- Any major deployment or profile-level change.
- Any action not explicitly classified as routine and allowlisted.
- Driver, firmware, BIOS/UEFI, boot, storage layout, security boundary, account/credential, firewall, network-stack, or system-recovery changes when those capabilities are introduced.
- Changes with destructive, irreversible, uncertain, or high-impact effects.
- Any action that exceeds configured scope, thresholds, frequency, or resource limits.
- Any policy change or request to increase Phoenix's own authority.

AI may explain, recommend, classify, and prepare a plan. AI cannot grant approval or alter the approval record.

#### Autonomous routine maintenance
Autonomous execution is a later capability, not an implicit permission granted by PHX-005. It may be enabled only for a named, versioned maintenance policy that:
- Uses a positive allowlist of action types and exact manifest identities.
- Has explicit exclusions and maximum change/count/time/resource thresholds.
- Is limited to a defined maintenance scope and schedule.
- Requires a valid machine-bound policy grant and an auditable run record.
- Performs preflight, freshness, idempotency and post-change verification.
- Uses transactional recovery where the operation is reversible.
- Defers any out-of-policy, ambiguous, high-risk, destructive, or irreversible action for human approval.
- Cannot edit or broaden its own policy/grant.

Initial routine-maintenance candidates may include read-only audit, reporting, and narrowly scoped repair of explicitly allowlisted low-risk application/settings drift. Application upgrades are not automatically included merely because the State Engine detects an outdated version. The allowlist must be explicit and reviewed.

#### Fail-closed behaviour
Missing policy, missing approval, ambiguous classification, validation failure, stale state, unsupported action, or unavailable verification means **do not mutate**. Log the reason and request operator intervention.

### 6. Interface shape
The implementation may refine exact parameter names to fit repository conventions, but the intended operator flow is:

```powershell
# Build and export a read-only plan
.\Bootstrap.ps1 -Plan

# Review and explicitly approve a specific plan
.\Bootstrap.ps1 -ApprovePlan ".\plans\deployment-plan-<id>.json"

# Execute only that plan and its matching approval
.\Bootstrap.ps1 -ExecutePlan ".\plans\deployment-plan-<id>.json"

# Existing default and transactional modes remain available and unchanged
.\Bootstrap.ps1
.\Bootstrap.ps1 -Transactional
```

Approval should be interactive and should show the plan ID, machine, scope, risk, action counts, and digest before the operator confirms. The implementation must reject incompatible switch combinations and must never silently fall back to normal orchestration.

### 7. Compatibility and non-goals
- Preserve the existing default `Bootstrap.ps1` orchestration path.
- Preserve the existing `-Transactional` behaviour unless a separately tested bug fix is required.
- Preserve the planner's current semantics, including `Outdated` applications planning as `Skip`.
- Preserve the existing Recovery engine as the sole rollback implementation.
- Do not introduce driver installation, firmware updates, OS snapshots, or new deployment capabilities under PHX-005.
- Do not claim a full OS-level atomic transaction. The guarantee is bounded to Phoenix-confirmed, supported, reversible changes.
- Do not enable autonomous routine maintenance by default in PHX-005.

## Alternatives considered

### Reuse `-Transactional` and add a confirmation prompt
Rejected. A prompt before normal orchestration does not prove the actions executed are the actions reviewed. It preserves the plan/execution disconnect.

### Re-run the profile after approval
Rejected. The profile may resolve to a different action set at execution time. That violates the exact-plan contract.

### Roll back every failed action
Rejected. A failed operation may have an uncertain post-state. Automatically reversing an unconfirmed change can cause additional damage. Only confirmed changes are eligible for automatic rollback.

### Give AI unrestricted approval authority
Rejected. AI is advisory and planning-capable, not an approval principal. Authority must come from a human operator or a separately reviewed, constrained maintenance policy.

## Consequences

Positive:
- The approved plan becomes the execution contract.
- Stale or modified plans fail closed.
- Execution is fail-fast and auditable.
- Existing deployment and recovery capabilities are reused rather than duplicated.
- Human authority is retained for initial builds and major changes.
- A constrained path is defined for future routine autonomy.

Trade-offs:
- Plans can be rejected when machine state changes after approval; operators must regenerate and reapprove.
- The first implementation requires additional plan, approval, execution and report schemas.
- Fail-fast execution may produce a smaller change ledger than the current full-orchestration transactional run.
- The initial digest/approval record is an integrity and accountability control, not a defence against a hostile local administrator.

## Acceptance
Implementation is accepted only when every mandatory criterion in [PHX-005 Plan-Gated Execution Specification](../specs/PHX-005-plan-gated-execution.md) passes, existing regression tests remain green, and CI passes on the feature branch.
