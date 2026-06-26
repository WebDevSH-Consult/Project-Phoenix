# 0005 — Structured Logging Framework

## Status
Accepted

## Context
Plain `Write-Host` output (e.g. "Installing Git...") is not searchable, not parseable, and gives no indication of timing or outcome.

## Decision
All modules log through a shared logging function that emits structured entries: timestamp, level (`INFO`/`SUCCESS`/`WARNING`/`ERROR`), message, and duration where applicable. Example:

```
[09:14:21] INFO    Installing Git...
[09:14:39] SUCCESS Git 2.52 installed (Duration: 18.2s)
```

Logs are written to `logs/` (gitignored, not committed) and are the source of truth for the health/report stage of the module lifecycle.

## Alternatives Considered
- **Free-text console output only**: rejected — not searchable or reportable.
- **Full structured JSON logging from day one**: deferred to a later version; plain leveled text is sufficient for v0.1–0.3 and easier to read during development.

## Consequences
The Dashboard and Reporting modules can parse `logs/` to build health objects and historical reports without re-running modules.
