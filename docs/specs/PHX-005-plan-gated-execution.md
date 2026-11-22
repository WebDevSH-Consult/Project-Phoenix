# PHX-005 — Plan-Gated Transactional Execution

**Status:** Architecture approved; implementation not started  
**Architecture decision:** [ADR 0019](../adr/0019-plan-gated-transactional-execution.md)  
**Target:** Phoenix v1.0 production hardening  
**Base:** v0.9.0 on `develop`

## Objective

Execute the exact deployment plan an operator approved, fail fast on the first unsuccessful action, and recover confirmed reversible changes through the existing Recovery engine. Preserve the current default and `-Transactional` paths.

The selected authority model is **hybrid**:
- Initial workstation builds and major/high-impact changes always require explicit human approval.
- Autonomous routine maintenance is permitted only in a later, explicitly enabled, tightly allowlisted policy.
- PHX-005 does not enable autonomous maintenance by default.

## Scope

### In scope
1. Versioned and integrity-checked deployment-plan artefact.
2. Explicit interactive approval artefact bound to one plan and target context.
3. Plan freshness and drift validation before mutation.
4. Dedicated plan executor that dispatches only approved supported actions.
5. Fail-fast sequencing.
6. Reuse of Installer, WindowsConfig and Recovery public operations.
7. Per-action verification and final-state reconciliation.
8. Transaction outcome and audit reporting.
9. PowerShell/Pester tests and CI coverage.
10. Operator documentation and safe CLI integration.

### Out of scope
- Driver, firmware, BIOS/UEFI, bootloader, disk partition or OS installation.
- OS snapshot/System Restore guarantees.
- New install or configuration capabilities.
- Autonomous maintenance policy execution (policy contract is defined, runtime implementation is a later milestone).
- AI self-approval or self-expansion of permissions.
- Replacing the existing normal orchestration or Recovery engines.

## Architecture

```text
                  READ-ONLY
       Deployment Planner + State Engine
                     |
                     v
             Versioned Plan JSON
                     |
                     v
             Operator Review
                     |
             Explicit Approval
                     |
                     v
              Approval Record
                     |
                     v
              Plan Executor
          /         |          \
   Integrity    Freshness    Policy /
   + schema     + machine    authority
          \         |          /
                     v
            Approved action set
                     |
           deterministic ordering
                     |
                     v
          Existing owning modules
          Installer / WindowsConfig
                     |
             verify each action
                     |
          +----------+-----------+
          |                      |
        Success                Failure
          |                      |
      Reconcile            Stop dispatch
          |                      |
      Commit report        Recovery engine
                                 |
                          Verify each undo
                                 |
                          Recovery report
```

### Module boundary

Add `modules/PlanExecutor` as an operator-invoked module, not a `module.json` orchestrated module. It coordinates existing capabilities and does not duplicate their mutation logic.

Proposed files:
- `modules/PlanExecutor/PlanExecutor.psd1`
- `modules/PlanExecutor/PlanExecutor.psm1`
- `modules/PlanExecutor/README.md`
- `tests/PlanExecutor.Tests.ps1`

The executor imports the required existing modules explicitly and uses their public functions. The exact functions and parameter contracts must be verified against source before implementation. Do not call private functions or copy/paste their behaviour.

## Artefact contracts

### Deployment plan
The plan must have:
- `SchemaVersion`
- `PlanId` (stable unique identifier)
- `CreatedAt` (UTC ISO 8601)
- `PhoenixVersion` and source revision when available
- `Machine` identity/context
- `Scope`
- `ConfigurationFingerprint` and manifest provenance/fingerprint
- `StateFingerprint` or equivalent relevant state snapshot
- `Actions` with stable action IDs, category, manifest identity, action, parameters, reason, risk, ordering/dependency metadata
- `Summary`
- `DigestAlgorithm` and canonical `PlanDigest`

Canonicalisation must be deterministic and documented. Exclude only explicitly non-semantic presentation fields (for example, console formatting). Never exclude action identity, parameters, scope, machine binding, dependency/order, configuration or relevant state. Reject unknown schema versions and duplicate action IDs.

### Approval record
Store separately from the plan. Include:
- Approval schema version and unique approval ID.
- Plan ID and exact canonical plan digest.
- Approver identity from the current Windows security principal.
- Approval decision and timestamp.
- Expiry.
- Machine and scope binding.
- Configuration/manifest fingerprint.
- Phoenix and plan schema versions.

Approval is a deliberate interactive confirmation after rendering the complete plan summary and digest. No default-yes behaviour. Non-interactive sessions fail closed for human approval. A digest is not a digital signature: document that a local administrator who can alter both files can defeat this initial control. Do not describe it as tamper-proof.

### Execution report
Include:
- Plan ID/digest and approval ID/approver.
- Executor and Phoenix versions.
- Start/end times and target machine.
- Freshness validation results.
- Ordered action results, including skipped/deferred entries.
- Confirmed changes and uncertain outcomes.
- First failure and reason.
- Rollback actions and verification results.
- Final transaction state: `Committed`, `RolledBack`, `RolledBackWithFailures`, `Rejected`, or `Interrupted/Unknown`.
- Report path and correlation identifiers.

## Execution algorithm

1. Resolve explicit plan path. Never silently choose the latest plan for execution.
2. Load and validate plan schema and required fields.
3. Canonicalise and verify plan digest.
4. Load the matching approval record; verify exact digest, ID, machine, scope, expiry, configuration and approver fields.
5. Validate supported actions and manifest identities. Reject unknown/unsupported/duplicate actions and invalid dependencies.
6. Recompute current state for the same scope and compare the semantic actionable set with the approved plan.
7. Recheck machine identity, elevation, configuration/manifests, preflight and relevant state.
8. Build deterministic execution order from approved action dependencies and existing run-order conventions.
9. Before each application install, recheck volatile installer preflight. If unsafe, fail before dispatch.
10. Dispatch only approved `Install` and `Apply` actions through existing public module operations. Record `Skip` and `Defer` as non-mutating outcomes.
11. Verify each action. Record a change as rollback-eligible only when the owning operation confirms it changed and verification succeeded.
12. On the first failed, unverifiable, or newly unsafe action, stop dispatching all later actions.
13. Call the existing Recovery engine for confirmed reversible changes only, in reverse execution order. Never automatically reverse an uncertain/partially applied action.
14. Reconcile actual final state and write the correlated execution report.
15. Return a non-zero failure result/exit status for rejected, failed, or incomplete transactions. Never fall back to normal orchestration.

## CLI contract

Proposed operator flow (names may be adjusted to repository conventions before coding):

```powershell
# Generate and export a read-only plan
.\Bootstrap.ps1 -Plan

# Review and explicitly approve a named plan
.\Bootstrap.ps1 -ApprovePlan ".\plans\deployment-plan-<id>.json"

# Execute only that plan and its matching approval
.\Bootstrap.ps1 -ExecutePlan ".\plans\deployment-plan-<id>.json"

# Existing paths remain available
.\Bootstrap.ps1
.\Bootstrap.ps1 -Transactional
```

Reject incompatible switch combinations. The execute path requires a specific plan path and its matching approval. It must not implicitly invoke profile orchestration or broaden the plan. Approval and execution should be distinct operations so the artefact can be reviewed and retained between them.

## Hybrid authority policy

### Human approval is mandatory
- Initial workstation provisioning/build.
- Major profile, configuration, or application-set changes.
- Any action not on a future explicit routine-maintenance allowlist.
- High-risk, destructive, irreversible, uncertain, or out-of-scope actions.
- Driver/firmware/BIOS/UEFI/boot/storage/security/account/credential/firewall/network-stack changes when supported in future.
- Any change to maintenance policy, thresholds, allowlists, or Phoenix authority.

AI can prepare and explain plans. AI cannot approve them.

### Future autonomous maintenance requirements
Autonomous maintenance is disabled by default and is not delivered by PHX-005. A later milestone must provide:
- Versioned policy with positive allowlist of action types and exact manifest identities.
- Explicit denylist and limits on scope, count, time, frequency and resource use.
- Machine-bound grant, schedule and audit record.
- Preflight, freshness, idempotency and post-change verification.
- Transactional recovery for reversible changes.
- Human escalation for any ambiguous, unlisted, high-impact, destructive or irreversible action.
- Policy protection so Phoenix cannot modify or broaden its own grant.
- Explicit operator enablement and revocation.

Read-only audit/reporting may be candidates. Repair and application upgrades are not automatically authorised by the fact that drift exists.

## Acceptance criteria

### A. Compatibility and regression
- [ ] Existing 218 Pester tests pass unchanged.
- [ ] Existing default `Bootstrap.ps1` behaviour remains unchanged.
- [ ] Existing `Bootstrap.ps1 -Transactional` behaviour remains unchanged.
- [ ] Existing planner output semantics remain unchanged, including `Outdated` => `Skip`.
- [ ] Existing Recovery engine remains the sole rollback implementation.
- [ ] No new module is accidentally discovered by normal orchestration.
- [ ] All existing required GitHub CI checks pass.

### B. Plan integrity and schema
- [ ] Plan schema is versioned and validated.
- [ ] Canonical digest is deterministic across repeated exports of equivalent semantic content.
- [ ] Any mutation to an execution-relevant plan field invalidates the digest.
- [ ] Unsupported schema, malformed plan, duplicate IDs, unknown actions/categories, invalid parameters, or missing manifest identity are rejected before mutation.
- [ ] Plan path is explicit; executor never selects a latest plan implicitly.
- [ ] Plan generation remains read-only.

### C. Approval and authority
- [ ] Approval requires an explicit affirmative interactive operator confirmation.
- [ ] Approval record identifies the Windows approver and binds exact plan ID/digest, machine, scope and configuration fingerprint.
- [ ] Missing, denied, mismatched, expired, malformed or wrong-machine approval is rejected.
- [ ] Non-interactive human approval fails closed.
- [ ] AI-generated text, a command-line presence flag, or an old approval artefact cannot approve a different plan.
- [ ] Human approval is required for initial builds and all major/high-impact/out-of-policy actions.
- [ ] Autonomous maintenance is disabled by default and cannot be enabled by PHX-005 execution.
- [ ] Phoenix cannot modify or expand its own authority.

### D. Freshness and drift
- [ ] Executor recomputes state for the same scope before first mutation.
- [ ] Any semantic action-set, parameter, dependency, machine, configuration or manifest change rejects execution.
- [ ] Non-semantic timestamps/presentation fields do not create false stale-plan rejections.
- [ ] A state change after approval that makes an action unnecessary or changes the required action causes rejection and replanning.
- [ ] Elevation and preflight are revalidated before execution.
- [ ] Application preflight is checked again immediately before each install.
- [ ] Unknown freshness state rejects execution rather than assuming safe.

### E. Exact execution and fail-fast
- [ ] Executor dispatches only approved `Install` and `Apply` actions.
- [ ] `Skip` and `Defer` are recorded and never dispatched.
- [ ] Executor never invokes normal profile orchestration as a substitute for the plan.
- [ ] Actions run in deterministic dependency/run order.
- [ ] First failure prevents every later action from starting.
- [ ] A rejected or failed plan never silently falls back to default deployment.
- [ ] Incompatible CLI switch combinations fail with actionable messages.
- [ ] Every dispatch and result is correlated to plan ID and action ID.

### F. Verification and recovery
- [ ] Every action uses the owning module's existing public apply/install function.
- [ ] Every successful action is verified using its owning module's verification path.
- [ ] Only positively confirmed changes are rollback-eligible.
- [ ] Uncertain or partially applied failed actions are surfaced and not blindly reversed.
- [ ] Recovery uses the existing shared `Invoke-PhoenixRollbackFromResults` / `Undo-*` path, not duplicated rollback code.
- [ ] Rollback runs in reverse execution order.
- [ ] Each rollback is verified and failures are surfaced.
- [ ] Final transaction state distinguishes clean rollback from partial rollback and unknown interruption.
- [ ] Final state is reconciled after commit or rollback.

### G. Reporting and observability
- [ ] Execution report records plan digest, approval identity, machine, scope and executor version.
- [ ] Report contains freshness checks, ordered action results, first failure, confirmed changes, uncertain outcomes and rollback results.
- [ ] Logs and reports do not expose secrets, credentials or sensitive tokens.
- [ ] Interrupted execution can be identified as incomplete/unknown and is never reported as committed.
- [ ] Operator receives a clear final summary and report location.

### H. Required Pester scenarios
- [ ] Happy path: approved fresh plan executes exact action set and commits.
- [ ] Plan tampering: altered plan rejected before first mutation.
- [ ] Approval tampering/mismatch: rejected before mutation.
- [ ] Expired and wrong-machine approval: rejected.
- [ ] Missing/denied/non-interactive approval: no mutation.
- [ ] Stale state/config/manifest and changed action set: rejected.
- [ ] Unknown action/schema/dependency cycle: rejected.
- [ ] Skip/Defer-only plan: no mutation, successful no-op report.
- [ ] First action fails: later actions are not invoked.
- [ ] Second action fails after first confirmed change: later actions stop and first change rolls back.
- [ ] Rollback failure: partial recovery accurately reported.
- [ ] Uncertain failed action: not automatically reversed.
- [ ] Preflight becomes unsafe between actions: stop before next install and recover prior confirmed changes.
- [ ] Elevation requirement changes: reject before mutation.
- [ ] Existing default and `-Transactional` regression tests remain green.
- [ ] Report correlation and secret redaction verified.

## Delivery slices

1. **PHX-005A — Plan/approval contracts:** schema, canonicalisation, digest, approval record, validation tests.
2. **PHX-005B — Freshness gate:** machine/config/state comparison and stale-plan tests.
3. **PHX-005C — Executor:** action dispatch through existing modules, deterministic ordering, fail-fast tests.
4. **PHX-005D — Transaction recovery:** adapt confirmed action results to Recovery's shared path, verify reverse order and partial rollback.
5. **PHX-005E — Bootstrap integration:** explicit approve/execute switches, compatibility tests, reports and documentation.
6. **PHX-005F — Release hardening:** full Pester suite, CI, manual isolated-VM validation, security review and v1.0 readiness assessment.

Each slice must be independently tested and reviewed. Do not begin the next slice while its predecessor has failing tests or unresolved safety findings.

## Definition of done
PHX-005 is complete only when all mandatory acceptance criteria pass, existing regression tests are green, CI is green, an isolated Windows test environment demonstrates approval-bound exact-plan execution and verified rollback, documentation matches implementation, and the operator explicitly accepts the resulting pull request. No production workstation deployment is used as the first end-to-end test.
