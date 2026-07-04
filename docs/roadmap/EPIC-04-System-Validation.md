# EPIC-04 — System Validation & Self-Healing

## Status

**In progress.** This epic tracks a broader scope than any single Roadmap milestone (see [ROADMAP.md](../../ROADMAP.md)); it's implemented incrementally as the modules it validates come online.

- **Shipped:** the `Validation` module (generic engine + hardware/tooling checks that exist today — GPU detection, PowerShell/WinGet/Git presence).
- **Planned:** application- and platform-specific checks (Steam, Epic, GameBar, AI tooling, URI handlers) — each lands alongside the installer module it validates, not before. Validating a launcher that Phoenix doesn't yet install would be untestable and premature.

## Goal

After deployment, Phoenix validates that Windows is fully operational and automatically repairs common issues where it's safe to do so.

## Objectives

- Detect hardware
- Detect missing Windows components
- Validate installed applications
- Validate URI handlers
- Validate Microsoft Store packages
- Validate gaming platform integrations
- Produce a deployment health report
- Offer automatic remediation where possible

## Validation Categories

### Hardware
- CPU
- GPU
- RAM
- Storage
- TPM
- Secure Boot

### Drivers
- AMD
- NVIDIA
- Intel
- Audio
- Network

### Windows
- WinGet
- PowerShell 7
- Windows Terminal
- VC++ Redistributables
- DirectX
- .NET

### Gaming
- Steam
- Epic Games
- FiveM
- Rockstar Games Launcher
- Xbox Services
- Game Bar

### URI Validation
- `ms-gamingoverlay:`
- `ms-xbox:`
- `ms-windows-store:`
- `ms-settings:`
- `ms-terminal:`

### AI
- Ollama
- Open WebUI
- Docker
- Claude CLI

## Deliverables

- Validation engine (generic PASS/WARN/FAIL contract, hardware-agnostic detection) — **shipped** in `modules/Validation`
- Installer preflight safety gate (no system-level install on a non-idle servicing state) — **shipped**, see ADR [0012](../adr/0012-installer-preflight-gate.md)
- HTML + JSON deployment report — **shipped** in `modules/Dashboard` (Roadmap 0.9)
- Self-healing / Recovery-Rollback engine — **planned** (the production-hardening focus toward v1.0)

## Self-Healing Lifecycle (planned)

The self-heal stage of the deployment pipeline (see [ARCHITECTURE.md](../../ARCHITECTURE.md#the-deployment-pipeline)) consolidates capabilities modules already have into one consistent flow:

```
Detect   → a check reports FAIL/WARN
   ↓
Repair   → apply a known, safe remediation
   ↓
Retry    → re-run the operation (Installer already does this)
   ↓
Rollback → restore prior state where a change made things worse
           (WindowsConfig already captures PreviousValue rollback data)
   ↓
Verify   → confirm the system is now healthy
```

The building blocks exist — `PreviousValue` rollback data, installer retry with re-validation, the preflight gate. The remaining work is making this an explicit, cross-module capability rather than per-module behaviour.

## Design Principles

Every check in this epic follows the "Validation First" standard in [CONTRIBUTING.md](../../CONTRIBUTING.md#validation-first): return PASS/WARN/FAIL with diagnostic detail, never assume a specific hardware vendor or that a Store package is present, log every result, and prefer safe self-healing over documentation when a fix is well-understood and reversible.
