# 0002 — Use PowerShell as the Primary Automation Language

## Status
Accepted

## Context
Project Phoenix automates a Windows workstation: installing applications, changing Windows settings, managing services, and inspecting system state.

## Decision
PowerShell (targeting PowerShell 7+, with Windows PowerShell compatibility where required) is the primary implementation language for all bootstrap and module logic.

## Alternatives Considered
- **Python**: excellent ecosystem, but weaker native access to Windows-specific APIs (registry, services, WMI/CIM) without extra dependencies. May still be used for auxiliary tooling.
- **Batch/CMD**: too limited for structured logging, objects, and error handling.

## Consequences
PowerShell's object pipeline maps cleanly onto the module health-object pattern. PSScriptAnalyzer becomes a first-class CI check.
