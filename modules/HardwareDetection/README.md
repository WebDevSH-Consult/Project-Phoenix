# HardwareDetection

The Hardware Detection Engine (ADR [0011](../../docs/adr/0011-hardware-detection-engine.md)). One authoritative answer to "what is this machine?" — detected, never assumed, per the engineering standards in [CONTRIBUTING.md](../../CONTRIBUTING.md#validation-first).

```powershell
$hardware = Get-PhoenixHardware

$hardware.Cpu.Vendor          # AMD | Intel | Unknown
$hardware.Gpus                # @({ Name; Vendor: AMD|NVIDIA|Intel|Unknown })
$hardware.MemoryGB
$hardware.System.FormFactor   # Laptop | Desktop
$hardware.System.IsVirtualMachine
$hardware.Tpm                 # Present | Absent | Unknown
$hardware.SecureBoot          # Enabled | Disabled | NotSupported | Unknown
$hardware.Disks               # @({ Model; SizeGB })
$hardware.NetworkAdapters
```

## Dual role

- **Orchestrated** at `RunOrder: 20` — hardware is detected, logged, and surfaced into the deployment report (via the `GetDetails` channel) before Windows is configured (40) or applications install (50).
- **Consumable** — any module can import this and call `Get-PhoenixHardware` directly. Detection is side-effect-free CIM reads, cheap enough to call on demand:

```powershell
if ((Get-PhoenixHardware).Gpus.Vendor -contains 'AMD') {
    # AMD-specific behaviour - detected, not assumed
}
```

## Honest unknowns

- An unrecognised CPU or GPU vendor is `Unknown`, never defaulted.
- TPM (`Get-Tpm`) and Secure Boot (`Confirm-SecureBootUEFI`) can require elevation or be unsupported on legacy BIOS — the wrappers return `Unknown`/`NotSupported` rather than guessing or throwing.

## Testability

Every system query goes through a thin mockable wrapper (`Get-PhoenixCimInstance`, `Get-PhoenixTpmState`, `Get-PhoenixSecureBootState`) — tests are deterministic regardless of the runner's hardware.

## History

`Get-PhoenixGpuInfo` moved here from [modules/Validation](../Validation/README.md), which now consumes it for its `Test-PhoenixGpu` check — detection is a hardware concern; judging state is a validation concern.
