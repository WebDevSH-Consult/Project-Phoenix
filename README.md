# 🔥 Project Phoenix

> A fully automated, AI-powered Windows workstation platform that can rebuild itself from a clean Windows installation.

[![Version](https://img.shields.io/badge/version-0.1.0--foundation-orange)](./CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

Project Phoenix is not a script. It is a platform: a modular, version-controlled, self-validating system for building, configuring, and maintaining a Windows workstation as Infrastructure-as-Code.

See [MANIFESTO.md](./MANIFESTO.md) for the philosophy, [ARCHITECTURE.md](./ARCHITECTURE.md) for system design, and [ROADMAP.md](./ROADMAP.md) for where this is headed.

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

**Version 0.1.0 — Foundation.** The project is currently establishing its repository structure, documentation, configuration schema, and CI pipeline before any automation logic is written. See [ROADMAP.md](./ROADMAP.md) for the full release plan.
