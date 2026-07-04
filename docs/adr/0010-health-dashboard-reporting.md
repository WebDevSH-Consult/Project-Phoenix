# 0010 — Health Dashboard and Deployment Reporting

## Status
Accepted

## Context
Phoenix runs end-to-end (configure Windows → install applications → validate) but the only record of what happened is the log stream. Roadmap 0.9 calls for a Health Dashboard: every run should end with a report stating exactly what Phoenix found, what it changed, and whether every step succeeded — the foundation for self-healing, deployment history, and CI artifact publishing later.

## Decision
A new engine module, `modules/Dashboard`, generates an HTML + JSON deployment report at the end of every `Bootstrap.ps1` run, written to `reports/` (gitignored runtime output, like `logs/`).

### Dashboard is an engine module, not an orchestrated one
The report must summarize the results of *all* orchestrated modules — data that only exists once `Invoke-PhoenixOrchestration` returns. A module running inside orchestration cannot see its siblings' health objects (the dispatcher deliberately doesn't share them). So `Bootstrap.ps1` imports Dashboard directly and calls `New-PhoenixDeploymentReport` with the collected results after orchestration — the same pattern as `PhoenixLogging`/`PhoenixConfig`/`PhoenixBootstrap`. No `module.json`.

### Modules surface detail through an optional `GetDetails` scriptblock
Per-item results (each application install, each setting with its previous value, each validation check) previously lived in module-private `$script:` variables, invisible outside the module. `Invoke-PhoenixModuleLifecycle` gains an optional `GetDetails` parameter: after the lifecycle completes, the dispatcher invokes it and attaches the result to the health object's new `Details` property. Modules opt in by adding one line to their definition; modules that don't (Example) are unaffected — the extension is purely additive, and a `GetDetails` failure degrades to `Details = $null` with a logged warning rather than failing the module.

### Report contents
Machine metadata (computer name, user, OS version), Phoenix version (`Get-PhoenixVersion`), git commit (mockable wrapper; `unknown` outside a repo), timestamp, run duration, GPU summary (consuming `Get-PhoenixGpuInfo` from Validation — the full Hardware Detection Engine is the next milestone, not smuggled in here), per-module health with per-item details, and derived counts of failures and warnings. HTML is a single self-contained file (inline CSS, values HTML-encoded, no external assets); JSON is the same report object serialized. Files are timestamped (`deployment-report-<yyyyMMdd-HHmmss>.html/.json`), consistent with `logs/` naming, so history accumulates instead of clobbering.

## Alternatives Considered
- **Dashboard as an orchestrated module at RunOrder 100**: rejected — it cannot see sibling module results from inside orchestration, and inverting that would mean the dispatcher sharing state between modules, breaking the isolation ADR 0006 established.
- **Parsing `logs/` to reconstruct results** (as ADR 0005 once suggested dashboards might): rejected for the primary path — structured objects already exist in memory at the end of the run; parsing text back into structure would be fragile duplication. Logs remain the searchable audit trail.
- **Fixed report filenames** (`deployment-report.html`, latest-wins): rejected in favour of timestamped files — deployment history is an explicit future goal, and clobbering it now to save a glob later is a poor trade.

## Consequences
Every run ends with a shareable, self-contained report. The `Details` channel gives future capabilities (self-healing, remediation suggestions, fleet reporting) structured data to act on without re-running anything. Adding report content for a new module costs one `GetDetails` line in its definition.
