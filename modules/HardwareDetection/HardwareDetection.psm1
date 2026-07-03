<#
    Phoenix Hardware Detection Engine (ADR 0011).

    One authoritative answer to "what is this machine?": CPU, GPUs, memory,
    form factor, virtualisation, motherboard, OS, TPM, Secure Boot, disks,
    and network adapters - detected, never assumed. Unknowns are reported as
    Unknown rather than guessed.

    Every system query goes through a thin mockable wrapper so tests are
    deterministic regardless of the runner's hardware.

    Depends on PhoenixLogging being imported first (for Write-PhoenixLog in
    the orchestrated lifecycle; the detection functions themselves do not log).
#>

#region Thin, mockable system-query wrappers

function Get-PhoenixCimInstance {
    <#
        .SYNOPSIS
        Thin, mockable wrapper around Get-CimInstance. Returns nothing
        (rather than throwing) when a class is unavailable.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ClassName
    )

    return @(Get-CimInstance -ClassName $ClassName -ErrorAction SilentlyContinue)
}

function Get-PhoenixTpmState {
    <#
        .SYNOPSIS
        Reports TPM state as Present/Absent/Unknown. Get-Tpm can require
        elevation; inaccessibility is Unknown, never a guess.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm.TpmPresent) { return 'Present' }
        return 'Absent'
    }
    catch {
        return 'Unknown'
    }
}

function Get-PhoenixSecureBootState {
    <#
        .SYNOPSIS
        Reports Secure Boot state as Enabled/Disabled/NotSupported/Unknown.
        Confirm-SecureBootUEFI throws on legacy BIOS and can require
        elevation; both degrade to honest states rather than guesses.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { return 'Enabled' }
        return 'Disabled'
    }
    catch [System.PlatformNotSupportedException] {
        return 'NotSupported'
    }
    catch {
        return 'Unknown'
    }
}

#endregion

#region Detection

function Get-PhoenixGpuInfo {
    <#
        .SYNOPSIS
        Detects installed GPUs without assuming any particular vendor.

        .DESCRIPTION
        Moved here from modules/Validation (its original home) per ADR 0011:
        detection is a hardware concern; Validation's Test-PhoenixGpu now
        consumes this. An adapter that doesn't match a known pattern is
        reported as Unknown rather than guessed at.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $adapters = Get-PhoenixCimInstance -ClassName 'Win32_VideoController'

    return @($adapters | ForEach-Object {
        $vendor = switch -Regex ($_.Name) {
            'AMD|Radeon' { 'AMD'; break }
            'NVIDIA|GeForce|Quadro' { 'NVIDIA'; break }
            'Intel' { 'Intel'; break }
            default { 'Unknown' }
        }
        [PSCustomObject]@{
            Name   = $_.Name
            Vendor = $vendor
        }
    })
}

function Get-PhoenixHardware {
    <#
        .SYNOPSIS
        Returns one object describing this machine: CPU, GPUs, memory,
        system/form factor, virtualisation, motherboard, OS, TPM, Secure
        Boot, disks, and enabled network adapters.

        .DESCRIPTION
        Side-effect-free CIM reads; cheap enough to call whenever hardware
        awareness is needed. Nothing is assumed: unrecognised vendors and
        inaccessible states are reported as Unknown.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $cpu = @(Get-PhoenixCimInstance -ClassName 'Win32_Processor') | Select-Object -First 1
    $cpuVendor = 'Unknown'
    if ($cpu) {
        $cpuVendor = switch -Regex ("$($cpu.Manufacturer)") {
            'AuthenticAMD|AMD' { 'AMD'; break }
            'GenuineIntel|Intel' { 'Intel'; break }
            default { 'Unknown' }
        }
    }

    $computerSystem = @(Get-PhoenixCimInstance -ClassName 'Win32_ComputerSystem') | Select-Object -First 1
    $enclosure = @(Get-PhoenixCimInstance -ClassName 'Win32_SystemEnclosure') | Select-Object -First 1
    $baseBoard = @(Get-PhoenixCimInstance -ClassName 'Win32_BaseBoard') | Select-Object -First 1
    $os = @(Get-PhoenixCimInstance -ClassName 'Win32_OperatingSystem') | Select-Object -First 1

    # Chassis types that indicate a portable machine (SMBIOS System Enclosure types)
    $laptopChassisTypes = @(8, 9, 10, 14, 30, 31, 32)
    $isLaptop = $false
    if ($enclosure -and $enclosure.ChassisTypes) {
        $isLaptop = [bool](@($enclosure.ChassisTypes) | Where-Object { $laptopChassisTypes -contains [int]$_ })
    }

    $isVirtualMachine = $false
    if ($computerSystem) {
        $isVirtualMachine = ("$($computerSystem.Manufacturer) $($computerSystem.Model)" -match 'Virtual|VMware|VirtualBox|QEMU|KVM|Xen|Parallels')
    }

    $memoryGB = 0
    if ($computerSystem -and $computerSystem.TotalPhysicalMemory) {
        $memoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)
    }

    $disks = @(Get-PhoenixCimInstance -ClassName 'Win32_DiskDrive' | ForEach-Object {
        [PSCustomObject]@{
            Model  = $_.Model
            SizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 0) } else { 0 }
        }
    })

    $networkAdapters = @(Get-PhoenixCimInstance -ClassName 'Win32_NetworkAdapter' | Where-Object { $_.NetEnabled -eq $true } | ForEach-Object { $_.Name })

    return [PSCustomObject]@{
        Cpu             = [PSCustomObject]@{
            Name              = if ($cpu) { "$($cpu.Name)".Trim() } else { 'Unknown' }
            Vendor            = $cpuVendor
            Cores             = if ($cpu) { [int]$cpu.NumberOfCores } else { 0 }
            LogicalProcessors = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { 0 }
        }
        Gpus            = @(Get-PhoenixGpuInfo)
        MemoryGB        = $memoryGB
        System          = [PSCustomObject]@{
            Manufacturer     = if ($computerSystem) { "$($computerSystem.Manufacturer)" } else { 'Unknown' }
            Model            = if ($computerSystem) { "$($computerSystem.Model)" } else { 'Unknown' }
            FormFactor       = if ($isLaptop) { 'Laptop' } else { 'Desktop' }
            IsVirtualMachine = $isVirtualMachine
        }
        Motherboard     = [PSCustomObject]@{
            Manufacturer = if ($baseBoard) { "$($baseBoard.Manufacturer)" } else { 'Unknown' }
            Product      = if ($baseBoard) { "$($baseBoard.Product)" } else { 'Unknown' }
        }
        OperatingSystem = [PSCustomObject]@{
            Caption     = if ($os) { "$($os.Caption)".Trim() } else { 'Unknown' }
            Version     = if ($os) { "$($os.Version)" } else { 'Unknown' }
            BuildNumber = if ($os) { "$($os.BuildNumber)" } else { 'Unknown' }
        }
        Tpm             = Get-PhoenixTpmState
        SecureBoot      = Get-PhoenixSecureBootState
        Disks           = $disks
        NetworkAdapters = $networkAdapters
    }
}

#endregion

#region Bootstrap Engine integration

function Get-HardwareDetectionModuleDefinition {
    <#
        .SYNOPSIS
        Returns the module definition hashtable consumed by
        Invoke-PhoenixModuleLifecycle, orchestrated via the Bootstrap Engine
        at RunOrder 20 - hardware is detected before anything decides.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name       = 'HardwareDetection'
        Initialize = {
            $script:PhoenixHardwareResults = @()
            Write-PhoenixLog -Level INFO -Message '[HardwareDetection] Detecting hardware...'
        }
        Validate   = { $true }
        Execute    = {
            $hardware = Get-PhoenixHardware

            $gpuSummary = ($hardware.Gpus | ForEach-Object { "$($_.Name) [$($_.Vendor)]" }) -join '; '
            Write-PhoenixLog -Level INFO -Message "[HardwareDetection] CPU: $($hardware.Cpu.Name) [$($hardware.Cpu.Vendor)], RAM: $($hardware.MemoryGB)GB, GPU: $gpuSummary"
            Write-PhoenixLog -Level INFO -Message "[HardwareDetection] System: $($hardware.System.Manufacturer) $($hardware.System.Model) ($($hardware.System.FormFactor)$(if ($hardware.System.IsVirtualMachine) { ', virtual machine' })), TPM: $($hardware.Tpm), Secure Boot: $($hardware.SecureBoot)"

            $script:PhoenixHardwareResults = @(
                [PSCustomObject]@{ Category = 'Hardware'; Name = 'CPU'; Status = (&{ if ($hardware.Cpu.Vendor -eq 'Unknown') { 'WARN' } else { 'PASS' } }); Message = "$($hardware.Cpu.Name) [$($hardware.Cpu.Vendor)], $($hardware.Cpu.Cores) cores / $($hardware.Cpu.LogicalProcessors) threads" }
                foreach ($gpu in $hardware.Gpus) {
                    [PSCustomObject]@{ Category = 'Hardware'; Name = 'GPU'; Status = (&{ if ($gpu.Vendor -eq 'Unknown') { 'WARN' } else { 'PASS' } }); Message = "$($gpu.Name) [$($gpu.Vendor)]" }
                }
                [PSCustomObject]@{ Category = 'Hardware'; Name = 'Memory'; Status = 'PASS'; Message = "$($hardware.MemoryGB) GB" }
                [PSCustomObject]@{ Category = 'Hardware'; Name = 'System'; Status = 'PASS'; Message = "$($hardware.System.Manufacturer) $($hardware.System.Model) ($($hardware.System.FormFactor)$(if ($hardware.System.IsVirtualMachine) { ', virtual machine' }))" }
                [PSCustomObject]@{ Category = 'Hardware'; Name = 'TPM'; Status = (&{ if ($hardware.Tpm -eq 'Present') { 'PASS' } else { 'WARN' } }); Message = $hardware.Tpm }
                [PSCustomObject]@{ Category = 'Hardware'; Name = 'Secure Boot'; Status = (&{ if ($hardware.SecureBoot -eq 'Enabled') { 'PASS' } else { 'WARN' } }); Message = $hardware.SecureBoot }
            )
        }
        Verify     = {
            @($script:PhoenixHardwareResults).Count -gt 0
        }
        GetDetails = { $script:PhoenixHardwareResults }
    }
}

#endregion

Export-ModuleMember -Function Get-PhoenixCimInstance, Get-PhoenixTpmState, Get-PhoenixSecureBootState, Get-PhoenixGpuInfo, Get-PhoenixHardware, Get-HardwareDetectionModuleDefinition
