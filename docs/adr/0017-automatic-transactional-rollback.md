# 0017 — Automatic Transactional Rollback

## Status
Accepted

## Context
ADR [0015](0015-recovery-rollback-engine.md) built the Recovery engine — reversible primitives (`Undo-PhoenixSettingChange`, `Undo-PhoenixApplicationInstall`), a plan builder (`Get-PhoenixRollbackPlan`), and an operator-invoked `Invoke-PhoenixRollback` that reverses a *past* deployment from its report. It explicitly **deferred** automatic rollback-on-failure, noting it "needs cross-module transactional state."

That state already exists. Every module runs through `Invoke-PhoenixModuleLifecycle`, whose `GetDetails` channel (ADR [0010](0010-health-dashboard-reporting.md)) runs unconditionally after Execute — so each module surfaces the changes it made (with `Changed = $true` and `PreviousValue`) even if it then failed. A completed orchestration therefore already produces a **complete, in-memory ledger of every confirmed change** — the same shape (`Modules[].Details[]`) that `Get-PhoenixRollbackPlan` consumes from a report. The missing piece is not new machinery; it is a **policy**: make a run all-or-nothing, and reverse it automatically when it doesn't fully succeed.

## Decision
Add an opt-in **transactional run**: `Bootstrap.ps1 -Transactional`. The run is all-or-nothing over Phoenix's reversible surface — if it does not fully succeed, Phoenix automatically reverses every confirmed change it made, in reverse order, each verified, and reports the outcome.

### Reuse, don't rebuild
This is the automatic, in-run trigger ADR 0015 deferred — **not** a second rollback mechanism. It reuses the Recovery engine wholesale:
- `Invoke-PhoenixRollback` (report-driven, operator-invoked) is refactored to delegate to a new **`Invoke-PhoenixRollbackFromResults -Results -RootPath`**, the in-memory sibling that reverses a set of lifecycle health results directly. Both share the exact same plan builder (`Get-PhoenixRollbackPlan`) and Undo-* primitives; the report path simply loads the report and passes `$report.Modules` to the results path. No reversal logic is duplicated.
- The forward orchestration path (`Invoke-PhoenixOrchestration`, `Invoke-PhoenixModuleLifecycle`) is **unchanged**. A transactional run executes exactly like a normal run, then evaluates the result and may roll back. Nothing about the non-transactional path changes.

### Commit criterion
A transactional run **commits** only if every module ends `Healthy`. If any module ends `Warning` (a setting/install that didn't verify) or `Error` (an unexpected exception), the run is considered failed and rolled back. This is deliberately strict — the point of a transaction is that partial state is worse than none — and it is *opt-in*, so the strictness is chosen, never imposed. The default run (no `-Transactional`) keeps today's behaviour: a failed module leaves earlier successful changes in place.

### Honest bounds — what "transactional" does and does not mean
- **Reversible surface only.** Phoenix reverses the changes it recorded and knows how to reverse: confirmed setting changes (restore the previous value, or remove a value it introduced) and applications it installed (uninstall). A confirmed change with no matching manifest is reported and skipped, never assumed undone (inherited from `Get-PhoenixRollbackPlan`).
- **Best-effort and verified, not guaranteed.** Every reversal is verified; a reversal that itself fails is surfaced as `FAIL`. If an undo fails, the machine is left partially changed and Phoenix says so — it never claims a clean rollback it did not achieve.
- **Not a snapshot or a database transaction.** There is no OS-level checkpoint. "Transactional" describes the all-or-nothing *intent* and the reverse-order, verify-each discipline — bounded to Phoenix's own recorded changes.
- **Complete ledger by design.** The run executes every module to completion before evaluating, precisely so the change ledger is complete. Fail-fast (stop at the first failure to avoid doing work that will be undone) is a deferred refinement — it would trade ledger completeness and a simpler design for less wasted work, and belongs with plan-gated execution (ADR 0016).

### Shape
- `Invoke-PhoenixRollbackFromResults -Results <health[]> -RootPath` (Recovery) — reverse a run's confirmed changes; returns the rollback results.
- `Bootstrap.ps1 -Transactional` — run orchestration, write the deployment report as usual, then: if every module is `Healthy`, log **transaction committed**; otherwise log **transaction failed — rolling back**, reverse via `Invoke-PhoenixRollbackFromResults`, and report what was reversed (and any reversal that failed).

## Alternatives Considered
- **Fail-fast rollback** (abort at the first failing module, then reverse): rejected for now. Because each module catches its own item-level failures and only assigns its `Details` on full return, running every module to completion yields a strictly more complete change ledger; fail-fast adds orchestration-loop surgery for the modest benefit of less wasted work. Deferred as a refinement.
- **Always-on transactional behaviour**: rejected. Silently reversing prior successful work on any warning would surprise operators and contradicts the project's detect-and-declare caution. Opt-in makes the strict semantics a deliberate choice.
- **A new in-run rollback engine separate from Recovery**: rejected as duplication. The Recovery engine's plan builder and primitives already do exactly this; the only gap was the trigger and an in-memory entry point.
- **OS snapshot / System Restore integration**: out of scope and dishonest to imply. Phoenix reverses its own recorded changes; it does not checkpoint the operating system.

## Consequences
A provisioning run can be made all-or-nothing with a single switch, and Phoenix will leave the machine as close to its pre-run state as its own reversible surface allows — reporting honestly where it could not. Because it reuses the Recovery engine end to end, the transactional path and the operator-invoked rollback path cannot drift: fixing or extending one improves both. The deferred refinements (fail-fast, plan-gated transactional execution, surfacing the rollback in the deployment report) all extend this without reworking it.
