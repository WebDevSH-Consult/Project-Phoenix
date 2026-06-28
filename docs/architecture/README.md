# Architecture Documentation

## Purpose

Holds detailed design material that goes beyond what fits in the top-level [ARCHITECTURE.md](../../ARCHITECTURE.md): diagrams, module-interaction notes, and design explorations for subsystems as they're built.

## Scope

Subsystem-level design (e.g. how the Application Installer module resolves WinGet vs. fallback installers, how the Dashboard aggregates health objects). Cross-cutting, project-wide architecture stays in the root [ARCHITECTURE.md](../../ARCHITECTURE.md); decisions with lasting rationale belong in [docs/adr](../adr/README.md) instead.

## Expected Contents

One file per subsystem or design topic, added as each module moves from skeleton to real implementation. Currently empty — populated as Sprint 1+ modules are designed.
