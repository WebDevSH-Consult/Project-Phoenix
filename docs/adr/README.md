# Architectural Decision Records

## Purpose

Records the significant architectural decisions made for Project Phoenix, along with the reasoning and alternatives considered. When a future contributor asks "why did we do it this way?", the answer should already be written down here rather than reconstructed from memory or git archaeology.

## Scope

Covers decisions with long-term consequences: choice of language and tooling (PowerShell, WinGet), structural conventions (folder layout, module contract), and platform-level tradeoffs (logging format, configuration design). It does not cover routine implementation details that belong in code comments or module documentation.

## Expected Contents

Numbered records following the pattern `NNNN-short-title.md`, each with a Status, Context, Decision, Alternatives Considered, and Consequences section. New ADRs are added as new decisions are made; existing ones are not rewritten after the fact — superseded decisions get a new ADR that references the old one (an ADR may also be *amended* by a later one, noted inline).

## Index

| # | Decision | Status |
|---|----------|--------|
| [0001](./0001-project-philosophy.md) | Project Philosophy: Platform, Not Scripts | Accepted |
| [0002](./0002-use-powershell.md) | Use PowerShell as the Primary Automation Language | Accepted |
| [0003](./0003-use-winget.md) | Use WinGet as the Primary Package Manager | Accepted |
| [0004](./0004-folder-structure.md) | Repository Folder Structure | Accepted |
| [0005](./0005-logging.md) | Structured Logging Framework | Accepted |
| [0006](./0006-module-manifest-and-orchestration.md) | Module Manifests and the Bootstrap Orchestration Engine | Accepted |
| [0007](./0007-application-deployment-engine.md) | Application Deployment Engine (Manifest-Driven Installer) | Accepted |
| [0008](./0008-workstation-profiles.md) | Workstation Profiles | Accepted |
| [0009](./0009-windows-configuration-engine.md) | Windows Configuration Engine (Data-Driven Settings) | Accepted |
| [0010](./0010-health-dashboard-reporting.md) | Health Dashboard and Deployment Reporting | Accepted |
| [0011](./0011-hardware-detection-engine.md) | Hardware Detection Engine | Accepted |
| [0012](./0012-installer-preflight-gate.md) | Installer Preflight Safety Gate | Accepted |
| [0013](./0013-elevation-strategy.md) | Elevation Strategy | Accepted |
| [0014](./0014-installer-completeness.md) | Installer Completeness: Dry-Run, Upgrade, Uninstall | Accepted |
| [0015](./0015-recovery-rollback-engine.md) | Recovery / Rollback Engine | Accepted |
| [0016](./0016-deployment-planner.md) | Intelligent Deployment Planner | Accepted (amended by 0018) |
| [0017](./0017-automatic-transactional-rollback.md) | Automatic Transactional Rollback | Accepted |
| [0018](./0018-desired-state-drift-management.md) | Desired State & Drift Management Engine (PHX-004) | Accepted |

> This table is maintained by hand. When adding an ADR, append a row here in the same commit.
