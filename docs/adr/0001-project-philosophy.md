# 0001 — Project Philosophy: Platform, Not Scripts

## Status
Accepted

## Context
A workstation automation effort can easily become an unorganised folder of one-off scripts that nobody, including the author, fully understands six months later.

## Decision
Project Phoenix is built as a platform: a central Phoenix Core that all modules route through, a configuration-driven design with no hard-coded preferences, a consistent module lifecycle (Initialise → Validate → Execute → Verify → Log → Report), and engineering discipline (CI, documentation, versioning, ADRs) from day one.

## Alternatives Considered
- **Loose script collection**: fastest to start, but unmaintainable and undocumented by design. Rejected.
- **Single monolithic script**: simpler short-term, but doesn't scale to gaming/AI/health/dashboard domains without becoming unreadable. Rejected.

## Consequences
Slower start (Sprint 0 produces no automation yet), but every subsequent feature has a stable foundation to slot into.
