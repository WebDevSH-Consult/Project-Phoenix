# 0013 — Elevation Strategy

## Status
Accepted

## Context
Several planned capabilities need administrator rights: HKLM policy settings (telemetry), Windows Features, service configuration, some driver installs. Until now Phoenix simply avoided them — `configs/windows.json`'s `DisableTelemetry` flag has been declared-but-inert since Sprint 0 (documented in ADR 0009). A strategy was needed before shipping any machine-scope operation.

## Decision
**Detect and declare — never auto-elevate.**

- `Test-PhoenixElevated` (in `modules/PhoenixCore` — a process-level concern, universally consumable) reports whether the current process holds administrator rights, via a mockable `WindowsPrincipal` check.
- Setting manifests gain an optional `RequiresElevation` field (default `false`).
- `Set-PhoenixSetting` checks **desired state first** — registry *reads* work without elevation, so a machine-scope setting already in its desired state is `PASS` regardless of rights, preserving idempotency.
- Only when a change is actually needed and the process lacks rights does the setting **skip with `WARN`**: "Requires elevation — not applied. Run Bootstrap from an elevated PowerShell to apply." A `WARN` doesn't fail the module (only `FAIL` does), so a non-elevated run stays `Healthy` with the skipped items plainly visible in the deployment report.
- `Bootstrap.ps1` logs elevation state at startup, warning up front that machine-scope settings will be skipped when running non-elevated.

The first machine-scope setting ships with this ADR: **telemetry minimization** (`HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection`, `AllowTelemetry = 1`), finally putting `windows.DisableTelemetry` to work. (`1` = Required diagnostic data only, the effective minimum on Windows Pro; `0` = Security tier applies only to Enterprise/Education and silently falls back elsewhere — honesty over a nicer-looking number.)

## Alternatives Considered
- **Auto-relaunch elevated (UAC prompt) when needed**: rejected. It surprises interactive users, breaks unattended runs (no one is present to click the prompt), spawns a second process whose logging/reporting would need re-plumbing, and violates "automation should never become a black box" (VISION.md).
- **Require Bootstrap to always run elevated**: rejected — violates least privilege for the majority of operations (HKCU settings, WinGet user installs, validation, reporting) that don't need it. The v1.0 unattended-rebuild scenario simply *runs* elevated; interactive partial runs shouldn't have to.
- **Per-operation elevation** (`Start-Process -Verb RunAs` around individual writes): rejected — one UAC prompt per setting is a terrible experience, and marshalling results back across process boundaries adds real complexity for no architectural gain.
- **`FAIL` instead of `WARN` for skipped machine-scope settings**: rejected — a missing right is not a broken system; the correct action ("re-run elevated") is fundamentally different from a genuine failure, and conflating them would make FAIL less trustworthy.

## Consequences
Machine-scope settings are now shippable: one JSON manifest with `RequiresElevation: true`. Non-elevated runs remain useful and safe, reporting exactly what they couldn't do and how to do it. Elevated runs apply everything. The same field and semantics extend naturally to future elevation-requiring work (Windows Features, services, application manifests) without new machinery. Windows Features and service configuration remain future work — this ADR covers *how* elevation is handled, not every capability that needs it.
