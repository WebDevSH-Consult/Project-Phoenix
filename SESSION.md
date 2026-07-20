# Project Phoenix Session Log

## Current Sprint
Workstation provisioning build-out (Roadmap 0.1–0.9 complete, working toward 1.0)

## Last Completed
- PHX-001 Repository Foundation (v0.1.0)
- Phoenix Core + Logging Engine (v0.2.0): `modules/PhoenixCore`, `modules/PhoenixLogging`, working `Bootstrap.ps1`, Pester suite, CI gating
- Roadmap 0.4 Configuration Engine: `modules/PhoenixConfig` (`Get-PhoenixConfiguration`), wired into `Bootstrap.ps1`
- PHX-002 Version Reporting (issue [#13](https://github.com/WebDevSH-Consult/Project-Phoenix/issues/13), closed)
- Roadmap 0.5 Bootstrap Engine: `modules/PhoenixBootstrap` — module discovery via `module.json`, dependency resolution, orchestration. ADR [0006](docs/adr/0006-module-manifest-and-orchestration.md).
- EPIC-04 System Validation (first slice): `modules/Validation` — hardware-agnostic PASS/WARN/FAIL engine; "Validation First" standard in `CONTRIBUTING.md`
- Roadmap 0.6 Application Deployment Engine: `modules/Installer` — manifest-driven (6 application manifests), idempotent install/retry/verify, WinGet/MSI/EXE backends, config-gated. ADR [0007](docs/adr/0007-application-deployment-engine.md).
- Roadmap 0.7 Workstation Profiles: `Invoke-PhoenixProfile Gaming` / `Development`. ADR [0008](docs/adr/0008-workstation-profiles.md). **v0.7.0 tagged and released.**
- Roadmap 0.8 Windows Configuration: `modules/WindowsConfig` — settings as JSON manifests (`Settings/*.json`), Registry (HKCU) provider, idempotent apply with previous-value rollback data and post-write verification. `configs/windows.json` flags finally live. `Get-PhoenixConfigValue` relocated to its canonical home in `PhoenixConfig`. ADR [0009](docs/adr/0009-windows-configuration-engine.md).
- Roadmap 0.9 Health Dashboard: `modules/Dashboard` — every `Bootstrap.ps1` run ends with a timestamped HTML + JSON deployment report under `reports/` (machine metadata, Phoenix version, git commit, GPU summary, duration, per-module health, per-item details, failure/warning counts). Enabled by a new optional `GetDetails` channel in `PhoenixCore` that Installer/WindowsConfig/Validation opt into. ADR [0010](docs/adr/0010-health-dashboard-reporting.md).
- Hardware Detection Engine: `modules/HardwareDetection` (`Get-PhoenixHardware`) — CPU/GPU/RAM/form-factor/VM/motherboard/OS/TPM/SecureBoot/disks/network as one detected-never-assumed object; orchestrated at `RunOrder: 20` and consumable by any module. GPU detection relocated here from Validation. Deployment reports now carry the full hardware summary. ADR [0011](docs/adr/0011-hardware-detection-engine.md).
- Installer Preflight safety gate: preflight checks in `modules/Validation` (`Get-PhoenixPreflightState` — pending reboot, `PendingFileRenameOperations`, active MSI session), gating `Install-PhoenixApplications` and `Invoke-PhoenixProfile` (nothing installs on `FAIL`; `-SkipPreflight` escape hatch). Validated against the live machine: it caught 21 real pending file operations including the AMD Adrenalin installer — the exact Error 206 scenario it was built to prevent. ADR [0012](docs/adr/0012-installer-preflight-gate.md).
- Elevation strategy: detect-and-declare, never auto-elevate (`Test-PhoenixElevated` in PhoenixCore; `RequiresElevation` manifest field; WARN-skip with "re-run elevated" when rights are missing; idempotent PASS still works non-elevated since reads need no rights). First machine-scope setting shipped: telemetry minimization — `windows.DisableTelemetry` finally live. ADR [0013](docs/adr/0013-elevation-strategy.md). **v0.8.0 tagged and released.**
- Installer completeness: dry-run (`-DryRun` previews the plan, no backend, skips preflight — PASS for no-op, WARN for pending change), upgrade (`Update-PhoenixApplication`, `winget upgrade`), and uninstall (`Uninstall-PhoenixApplication`, `winget uninstall`/`msiexec /x`, verified gone; EXE unsupported). Operator-invoked; the engine is now feature-complete for v1.0. ADR [0014](docs/adr/0014-installer-completeness.md).
- Recovery / Rollback Engine: `modules/Recovery` (`Invoke-PhoenixRollback`) reverses a deployment — restore settings to their `PreviousValue` (or remove ones Phoenix introduced), uninstall apps it installed — driven by the deployment report's confirmed changes (`Changed` flag now on setting/install results), in reverse order, each verified. The pipeline's Self-Heal stage made real. Operator-invoked. ADR [0015](docs/adr/0015-recovery-rollback-engine.md). Verified against the live registry.
- Intelligent Deployment Planner: `modules/DeploymentPlanner` — the orchestration "brain." `New-PhoenixDeploymentPlan` builds an explainable, exportable plan before anything changes (per-item `Install`/`Apply`/`Skip`/`Defer` + reason), reusing the executors' own predicates so the plan matches a real run; the header carries detected hardware. `Bootstrap.ps1 -Plan` shows/exports a config-scoped plan and exits without executing (review before deploy). Estimates/risk are declared coarse heuristics; plan-gated execution deferred to pair with auto-rollback. ADR [0016](docs/adr/0016-deployment-planner.md). Verified end-to-end against the live machine (correctly skipped installed apps, deferred an install behind a real pending-file-op, deferred the elevation-gated telemetry setting).
- PHX-004 Slice 2 — Repair: `Invoke-PhoenixRepair` re-applies desired state for **only** the drifted items (never a profile redeploy), reusing the owning module for each fix (`Install-`/`Update-PhoenixApplication`, `Set-PhoenixSetting`) so every repair is idempotent and self-verifying. Settings before applications; preflight gates application repairs only (settings continue — a registry write is not an install); `-DryRun` previews; `-Transactional` reverses changed repairs on failure via the Recovery engine. A *version* repair is deliberately non-reversible (undoing an upgrade by uninstalling would destroy a legitimately-installed app). Phoenix now fixes, not just knows.
- Desired State & Drift Management Engine (PHX-004, Slice 1): `modules/StateEngine` — the single source of truth for current-vs-desired state; Phoenix can now *maintain*, not just deploy. `Get-PhoenixState` builds the state model (apps `Missing`/`Outdated`/`Present`, settings `Modified`/`Applied`) by orchestrating existing predicates; `Compare-PhoenixState` returns the drift set; `Invoke-PhoenixAudit` reports drift + writes a JSON artifact under `audits/`. Read-only. Desired = manifests in scope; honest drift surface (presence, version, registry) — drivers/services deferred. Added read-only WinGet probe `Test-PhoenixApplicationOutdated` in Installer. ADR [0018](docs/adr/0018-desired-state-drift-management.md). Verified live: flagged a missing app + an elevation-gated setting as drift, no version false positives. Slice 2 (`Invoke-PhoenixRepair`) is next.
- Automatic Transactional Rollback: `Bootstrap.ps1 -Transactional` makes a run all-or-nothing — runs normally, then if any module does not end `Healthy`, automatically reverses every confirmed change the run made (in reverse order, each verified) and reports committed / rolled-back / rolled-back-with-failures. New `Invoke-PhoenixRollbackFromResults` (in `modules/Recovery`) reverses from live run results; `Invoke-PhoenixRollback` now delegates to it, so the report-driven and in-run paths share one plan builder + `Undo-*` primitives and can't drift. Forward orchestration path untouched; opt-in; honest bounds (reversible surface only, best-effort + verified, not an OS snapshot). ADR [0017](docs/adr/0017-automatic-transactional-rollback.md). This closes the rollback-on-failure item ADR 0015 deferred.

## Current Task
- None in progress — awaiting next task selection

## Next Planned Task
- PHX-004 State Engine, Slice 3: refactor the Deployment Planner (ADR 0016) to consume `Compare-PhoenixState` as its current-vs-desired source instead of calling the predicates inline — making the State Engine the single source of truth. A dedupe, not a semantics change (both use the same predicates today).
- Then, production-hardening toward v1.0:
  1. Plan-gated transactional execution — combine the Deployment Planner (ADR 0016) with the transactional run (ADR 0017): execute the reviewed plan, not the profile, as one all-or-nothing transaction. Fail-fast (stop at first failure) is the related refinement.
  2. Final v1.0 polish and the release
- Also pending: decide EPIC numbering for a "Hardware Awareness" epic doc (EPIC-05 was informally used for the Application Deployment Platform; suggest EPIC-06)

## Repository Health
- Core roadmap (0.1–0.9) complete, plus Hardware Detection, the Installer Preflight gate, and the Elevation strategy.
- Phase has shifted from feature development to **production hardening**: installer completeness, recovery/rollback, and v1.0 readiness. The goal now is that every module consistently follows the Phoenix Deployment Lifecycle — now a formal project standard in [ARCHITECTURE.md](ARCHITECTURE.md#standard-the-phoenix-deployment-lifecycle) and [CONTRIBUTING.md](CONTRIBUTING.md#module-standards) — not that more modules exist.
- EPIC-04 (System Validation & Self-Healing) in progress alongside the versioned milestones.

## Blockers
- None currently. Known friction (not blocking): `develop`'s ruleset up-to-date requirement vs `main→develop` sync PRs — documented in `docs/standards/branch-protection.md`. Mitigation that worked for v0.7.0: cut the release branch from `develop` with `main` merged in first (content no-op), avoiding any ruleset changes.

## Notes
- v0.7.0 tagged and released: https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.7.0
- Repository is public; branch rulesets active on `main`/`develop` (PR required, 5 CI checks required, no force-push/deletion).
- CI passing on `develop` HEAD.
- Repository Metrics below are computed by hand (`find`/`grep` counts) at the end of each session. **Post-v1.0 candidate:** have Phoenix generate these itself — either a CI step or a small addition to the Health Dashboard — so the numbers are always accurate and never drift. Deliberately deferred: it's a quality-of-life improvement, not v1.0-blocking.
- WindowsConfig now supports HKLM via the elevation strategy (ADR 0013): machine-scope settings apply when Bootstrap runs elevated, skip with a clear WARN otherwise. `DisableTelemetry` is live. Windows Features and service configuration remain future manifest `Type`s.
- New engineering standing rules adopted this week: detect hardware before deciding, never assume AMD/NVIDIA or Store packages, validate every installation, tests for every deployment module, prefer self-healing over documentation.

## Current Repository Metrics

Modules: 13
Tests: 215
PowerShell Files: 40
Markdown Documents: 55
GitHub Workflows: 1
CI Status: Passing
Open Issues: 0
Open PRs: 0
