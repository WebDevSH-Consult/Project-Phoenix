# 0003 — Use WinGet as the Primary Package Manager

## Status
Accepted

## Context
Application installation needs a reliable, scriptable package manager that doesn't require a third-party agent.

## Decision
WinGet is the primary installation mechanism for the Application Installer module. Configuration in `configs/applications.json` maps to WinGet package IDs.

## Alternatives Considered
- **Chocolatey**: mature and widely used, but requires a separate install step and community-maintained package quality varies. May be supported as a fallback for packages absent from WinGet.
- **Manual installers**: not scriptable/idempotent. Rejected as a default path.

## Consequences
The Installer module needs a fallback path for packages not available via WinGet, documented per-application in `configs/applications.json`.
