# Dashboard

The Health Dashboard (Roadmap 0.9). Every `Bootstrap.ps1` run ends with an HTML + JSON deployment report under `reports/` stating what Phoenix found, what it changed, and whether every step succeeded. See [ADR 0010](../../docs/adr/0010-health-dashboard-reporting.md).

## Why this is an engine module (no `module.json`)

The report summarizes the results of **all** orchestrated modules — data that only exists once `Invoke-PhoenixOrchestration` returns. A module inside orchestration can't see its siblings' health objects (module isolation, ADR 0006). So `Bootstrap.ps1` imports Dashboard directly and calls it last, the same pattern as `PhoenixLogging`/`PhoenixConfig`/`PhoenixBootstrap`.

## The `Details` channel

Per-item results (each install, each setting with its previous value, each validation check) are surfaced by modules through the optional `GetDetails` scriptblock in their lifecycle definition — a purely additive PhoenixCore extension. Modules that don't opt in simply have `Details = $null`; a failing `GetDetails` degrades to a logged warning, never a module failure.

## Report contents

| Section | Source |
|---|---|
| Machine (computer, user, OS) | `System.Environment` |
| Phoenix version | `Get-PhoenixVersion` (`VERSION` file) |
| Git commit | `Get-PhoenixGitCommit` (mockable; `unknown` outside a git checkout) |
| Duration | Measured by `Bootstrap.ps1` |
| Hardware (CPU, GPUs, memory, form factor, TPM, Secure Boot, ...) | `Get-PhoenixHardware` from [HardwareDetection](../HardwareDetection/README.md) |
| Module health + per-item details | Orchestration results + the `Details` channel |
| Failure/warning counts | Derived from the above |

## Output

Timestamped, so history accumulates (consistent with `logs/`):

```
reports/
    deployment-report-20260703-091421.html   ← self-contained, inline CSS, no external assets
    deployment-report-20260703-091421.json   ← the same report object, machine-readable
```

`reports/` is gitignored runtime output, like `logs/`.
