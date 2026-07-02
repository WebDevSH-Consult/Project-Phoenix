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
- Self-healing engine (safe, logged, opt-in remediation) — **planned**, extended per-category as installer modules exist to remediate against
- HTML deployment report — **planned**, depends on the Health Dashboard milestone (Roadmap 0.9)
- JSON validation report — **planned**

## Design Principles

Every check in this epic follows the "Validation First" standard in [CONTRIBUTING.md](../../CONTRIBUTING.md#validation-first): return PASS/WARN/FAIL with diagnostic detail, never assume a specific hardware vendor or that a Store package is present, log every result, and prefer safe self-healing over documentation when a fix is well-understood and reversible.
