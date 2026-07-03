# 0011 — Hardware Detection Engine

## Status
Accepted

## Context
The engineering standards say "detect hardware before deciding; never assume AMD or NVIDIA hardware" — but until now the only detection Phoenix had was GPU vendor inference living inside `modules/Validation`. Upcoming capabilities (GPU-vendor-conditional driver installs, laptop-vs-desktop profiles, the installer preflight safety gate, TPM/Secure Boot reporting) all need one authoritative answer to "what is this machine?".

## Decision
A new module, `modules/HardwareDetection`, exposing `Get-PhoenixHardware`: a single object describing CPU (name, vendor, cores), GPUs (name, vendor), memory, system (manufacturer, model, laptop/desktop form factor, virtual-machine detection), motherboard, operating system, TPM state, Secure Boot state, physical disks, and enabled network adapters.

- **Both orchestrated and consumable.** The module carries a `module.json` at `RunOrder: 20` — hardware is detected (and logged, and surfaced into the deployment report via the `GetDetails` channel) before Windows is configured (40) or applications install (50). Any module can also import it and call `Get-PhoenixHardware` directly; detection is cheap, side-effect-free CIM reads.
- **GPU detection moves here from `modules/Validation`** — the same canonical-home reasoning as `Get-PhoenixConfigValue`'s move to `PhoenixConfig` (ADR 0009): detection is a hardware concern, not a validation concern. `Test-PhoenixGpu` remains in Validation as a *check* but consumes `Get-PhoenixGpuInfo` from here.
- **Unknowns stay Unknown.** TPM (`Get-Tpm`) and Secure Boot (`Confirm-SecureBootUEFI`) can require elevation or be unsupported on legacy BIOS; the wrappers return `Unknown`/`NotSupported` rather than guessing or throwing. An unrecognised CPU or GPU vendor is `Unknown`, never defaulted.
- **Every system query goes through a thin mockable wrapper** (`Get-PhoenixCimInstance`, `Get-PhoenixTpmState`, `Get-PhoenixSecureBootState`) so tests are deterministic regardless of the runner's hardware — the same standard as every other module.

## Alternatives Considered
- **Engine module without orchestration** (like Dashboard): rejected — detection results belong in the deployment report ("what Phoenix found"), and running first in orchestration is exactly what the report needs; the dual role costs one `module.json`.
- **Leaving GPU detection in Validation and duplicating CPU/RAM/etc. detection there**: rejected — Validation's job is judging state (PASS/WARN/FAIL), not describing hardware. Splitting detection across modules is how "never assume" rules erode.
- **Third-party hardware inventory tooling**: rejected — CIM/WMI covers everything needed with zero dependencies.

## Consequences
Future conditional logic reads as intended: `if ((Get-PhoenixHardware).Gpus.Vendor -contains 'AMD') { ... }`. The deployment report gains a full hardware section. The installer preflight gate (next task) has a natural home for its system-state queries alongside these wrappers. Laptop/VM/TPM/Secure Boot awareness becomes available to profiles and future driver modules without any of them touching CIM directly.
