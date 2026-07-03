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

## Current Task
- None in progress — awaiting next task selection

## Next Planned Task
- Toward v1.0, in agreed order:
  1. **Installer Preflight / Driver Install Guard** — a system-state safety gate before any system-level install (pending reboot, `PendingFileRenameOperations`, active installer sessions), integrated with the Validation PASS/WARN/FAIL engine and respected by the Installer. Motivated by the real-world AMD Error 206 failure: not a feature, a missing safety layer. Universal — applies to WinGet/MSI/EXE, not just drivers.
  2. Elevation strategy ADR + HKLM settings (unblocks `DisableTelemetry`, Windows Features, services)
  3. Installer completeness: dry-run mode, WinGet upgrade/uninstall
  4. Advanced validation + self-healing slices, then v1.0 release
- Also pending: decide EPIC numbering for a "Hardware Awareness" epic doc (EPIC-05 was informally used for the Application Deployment Platform; suggest EPIC-06)

## Repository Health
- 90% toward v1.0 (9 of 10 Roadmap milestones complete: 0.1–0.9)
- EPIC-04 (System Validation & Self-Healing) in progress alongside the versioned milestones

## Blockers
- None currently. Known friction (not blocking): `develop`'s ruleset up-to-date requirement vs `main→develop` sync PRs — documented in `docs/standards/branch-protection.md`. Mitigation that worked for v0.7.0: cut the release branch from `develop` with `main` merged in first (content no-op), avoiding any ruleset changes.

## Notes
- v0.7.0 tagged and released: https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.7.0
- Repository is public; branch rulesets active on `main`/`develop` (PR required, 5 CI checks required, no force-push/deletion).
- CI passing on `develop` HEAD.
- Repository Metrics below are computed by hand (`find`/`grep` counts) at the end of each session — no automated script generates them yet. Worth automating once it becomes tedious.
- WindowsConfig is HKCU-only by design for now; HKLM (telemetry policy, Windows Features, services) waits on an elevation-strategy ADR. `configs/windows.json`'s `DisableTelemetry` stays declared-but-inert until then (documented in the module README).
- New engineering standing rules adopted this week: detect hardware before deciding, never assume AMD/NVIDIA or Store packages, validate every installation, tests for every deployment module, prefer self-healing over documentation.

## Current Repository Metrics

Modules: 10
Tests: 119
PowerShell Files: 31
Markdown Documents: 44
GitHub Workflows: 1
CI Status: Passing
Open Issues: 0
Open PRs: 0
