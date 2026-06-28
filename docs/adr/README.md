# Architectural Decision Records

## Purpose

Records the significant architectural decisions made for Project Phoenix, along with the reasoning and alternatives considered. When a future contributor asks "why did we do it this way?", the answer should already be written down here rather than reconstructed from memory or git archaeology.

## Scope

Covers decisions with long-term consequences: choice of language and tooling (PowerShell, WinGet), structural conventions (folder layout, module contract), and platform-level tradeoffs (logging format, configuration design). It does not cover routine implementation details that belong in code comments or module documentation.

## Expected Contents

Numbered records following the pattern `NNNN-short-title.md` (see [0001-project-philosophy.md](./0001-project-philosophy.md) onward), each with a Status, Context, Decision, Alternatives Considered, and Consequences section. New ADRs are added as new decisions are made; existing ones are not rewritten after the fact — superseded decisions get a new ADR that references the old one.
