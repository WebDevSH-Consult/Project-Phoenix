# 🔥 Project Phoenix

> A fully automated, AI-powered Windows workstation platform that can rebuild itself from a clean Windows installation.

[![Version](https://img.shields.io/badge/version-0.9.0--hardening-orange)](./CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

Project Phoenix is not a script. It is a platform: a modular, version-controlled, self-validating system for building, configuring, and maintaining a Windows workstation as Infrastructure-as-Code.

See [VISION.md](./VISION.md) for the long-term direction, [MANIFESTO.md](./MANIFESTO.md) for the philosophy, [ARCHITECTURE.md](./ARCHITECTURE.md) for system design, and [ROADMAP.md](./ROADMAP.md) for where this is headed.

---

## Quick Start

```powershell
.\Bootstrap.ps1
```

Phoenix reads `configs/phoenix.json` and the per-domain config files, decides what needs doing, and executes through Phoenix Core. Nothing is hard-coded — preferences live in configuration, not in code.

---

## Repository Structure

```
Project-Phoenix/
│
├── .github/            CI workflows, issue/PR templates, CODEOWNERS
├── bootstrap/          Bootstrap launcher logic
├── modules/            Phoenix Core modules (Windows, Installer, Gaming, AI, Health, Dashboard)
├── configs/            JSON configuration (phoenix.json, applications.json, gaming.json, ...)
├── templates/          Reusable templates
├── docs/               Documentation, ADRs, architecture diagrams
├── tests/              Module and integration tests
├── scripts/            Standalone utility scripts
├── assets/             Static assets
├── dashboard/          Health dashboard
├── installers/         Installer module assets
├── logs/               Runtime logs (not committed)
├── reports/            Deployment reports, HTML + JSON (not committed)
├── temp/               Scratch space (not committed)
│
├── Bootstrap.ps1       Single entry point
├── phoenix.json        Root configuration
├── README.md
├── MANIFESTO.md
├── ARCHITECTURE.md
├── CONTRIBUTING.md
├── ROADMAP.md
├── CHANGELOG.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── PROJECT_CHARTER.md
└── LICENSE
```

---

## Branching & Contribution

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full branch strategy, commit standards, and PR process. In short:

- `main` — protected, stable releases only.
- `develop` — default development branch.
- `feature/*`, `bugfix/*`, `docs/*`, `experiment/*` — all work happens here, reviewed via PR into `develop`.

## Status

**Version 0.9.0 — Planning, Recovery & Configuration Management.** The numbered roadmap (0.1–0.9) is complete, and Phoenix has crossed from *provisioning* into *configuration management*:

- **It plans before it acts.** `Bootstrap.ps1 -Plan` builds an explainable, exportable deployment plan — every action with a reason — and exits without executing. Review before deploy ([ADR 0016](./docs/adr/0016-deployment-planner.md)).
- **It undoes what it did.** `Invoke-PhoenixRollback` reverses a past deployment; `Bootstrap.ps1 -Transactional` makes a run all-or-nothing, automatically reversing its own changes if any module fails ([ADR 0015](./docs/adr/0015-recovery-rollback-engine.md), [0017](./docs/adr/0017-automatic-transactional-rollback.md)).
- **It maintains, not just deploys.** `Invoke-PhoenixAudit` detects drift from declared state; `Invoke-PhoenixRepair` fixes *only* the drift — never a reinstall it doesn't need ([ADR 0018](./docs/adr/0018-desired-state-drift-management.md)).

On top of the 0.8.0 foundation: orchestration, the manifest-driven installer (now with dry-run, upgrade and uninstall), workstation profiles, Windows Configuration, the Health Dashboard, hardware detection, the installer preflight gate, and a detect-and-declare elevation strategy. Every module follows the deployment pipeline defined in [ARCHITECTURE.md](./ARCHITECTURE.md). Remaining work toward 1.0 is polish rather than capability. See [ROADMAP.md](./ROADMAP.md).
