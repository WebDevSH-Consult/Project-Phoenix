# Architecture

## Overview

Project Phoenix is built around a single entry point and a central core. No module talks to another module directly — everything routes through Phoenix Core.

```
                    Bootstrap.ps1
                          │
                          ▼
                   Phoenix Core
                          │
      ┌───────────────────┼───────────────────┐
      ▼                   ▼                   ▼
 Windows Module     Installer Module     Health Module
      ▼                   ▼                   ▼
 Gaming Module          AI Module       Dashboard Module
      ▼
 Configuration Manager
```

## Module Lifecycle

Every module — without exception — follows the same six-stage lifecycle:

1. **Initialise** — load configuration, prepare state.
2. **Validate** — confirm preconditions are met (permissions, dependencies, disk space, etc.).
3. **Execute** — perform the actual work.
4. **Verify** — confirm the work had the intended effect.
5. **Log** — emit structured log entries for every action.
6. **Report** — return a health/result object to Phoenix Core.

## Health Objects

Every module returns a health object consumed by the Dashboard module. Example shape:

```json
{
  "module": "Windows",
  "healthPercent": 98,
  "status": "Warning",
  "lastRun": "2026-06-26T09:14:21Z",
  "issues": ["Telemetry service re-enabled by Windows Update"]
}
```

## Logging

Logs are structured, not free text:

```
[09:14:21] INFO    Installing Git...
[09:14:39] SUCCESS Git 2.52 installed (Duration: 18.2s)
```

Every action is timestamped, leveled, and searchable. See ADR [0005-logging.md](./docs/adr/0005-logging.md).

## Configuration

Nothing is hard-coded. Behaviour is driven entirely by `configs/*.json`. Phoenix Core reads configuration; it does not contain preferences itself.

```json
{
  "InstallGit": true,
  "InstallPython": true,
  "InstallDocker": false,
  "InstallEpic": true,
  "InstallSteam": true,
  "InstallBattleNet": true
}
```

## Architectural Decisions

Significant decisions (why PowerShell, why WinGet, why this folder structure, etc.) are recorded as Architectural Decision Records in [docs/adr/](./docs/adr/). When in doubt about *why* something was built a certain way, check there before changing it.
