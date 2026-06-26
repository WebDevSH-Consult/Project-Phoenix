# 0004 — Repository Folder Structure

## Status
Accepted

## Context
The repository needs a structure that scales from "foundation only" (v0.1) to a full multi-module platform (v1.0) without reorganisation.

## Decision
Top-level folders are organised by concern, not by feature: `bootstrap/` (launcher), `modules/` (Phoenix Core modules), `configs/` (JSON configuration), `templates/`, `docs/` (including `adr/`), `tests/`, `scripts/`, `assets/`, `dashboard/`, `installers/`, `logs/`, `temp/`, plus a `.github/` directory for CI and repository governance.

## Alternatives Considered
- **Feature-first folders** (e.g. `gaming/`, `ai/` at top level each containing their own scripts/configs/tests): rejected because it duplicates structure per feature and makes cross-cutting CI checks harder.

## Consequences
Modules live under `modules/<ModuleName>/` and are expected to mirror the lifecycle pattern internally. Configuration is centralised under `configs/`, not scattered per module.
