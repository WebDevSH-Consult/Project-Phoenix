Describe 'Get-PhoenixGpuInfo' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/HardwareDetection/HardwareDetection.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'identifies an AMD adapter without assuming AMD' {
        Mock -ModuleName HardwareDetection Get-PhoenixCimInstance {
            @([PSCustomObject]@{ Name = 'AMD Radeon RX 7900 XT' })
        }

        $gpus = Get-PhoenixGpuInfo

        $gpus[0].Vendor | Should -Be 'AMD'
    }

    It 'identifies an NVIDIA adapter without assuming NVIDIA' {
        Mock -ModuleName HardwareDetection Get-PhoenixCimInstance {
            @([PSCustomObject]@{ Name = 'NVIDIA GeForce RTX 4080' })
        }

        (Get-PhoenixGpuInfo)[0].Vendor | Should -Be 'NVIDIA'
    }

    It 'reports an unrecognised adapter as Unknown, never guessed' {
        Mock -ModuleName HardwareDetection Get-PhoenixCimInstance {
            @([PSCustomObject]@{ Name = 'Some Unbranded Display Adapter' })
        }

        (Get-PhoenixGpuInfo)[0].Vendor | Should -Be 'Unknown'
    }
}

Describe 'Get-PhoenixHardware' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/HardwareDetection/HardwareDetection.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-CimFixture {
            param([string]$Manufacturer = 'Micro-Star International', [string]$Model = 'MS-7D75', [int[]]$ChassisTypes = @(3))

            Mock -ModuleName HardwareDetection Get-PhoenixCimInstance {
                param($ClassName)
                switch ($ClassName) {
                    'Win32_Processor' { @([PSCustomObject]@{ Name = 'AMD Ryzen 7 7800X3D'; Manufacturer = 'AuthenticAMD'; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }) }
                    'Win32_VideoController' { @([PSCustomObject]@{ Name = 'AMD Radeon RX 7900 GRE' }) }
                    'Win32_ComputerSystem' { @([PSCustomObject]@{ Manufacturer = $Manufacturer; Model = $Model; TotalPhysicalMemory = 34282912256 }) }
                    'Win32_SystemEnclosure' { @([PSCustomObject]@{ ChassisTypes = $ChassisTypes }) }
                    'Win32_BaseBoard' { @([PSCustomObject]@{ Manufacturer = 'MSI'; Product = 'B650 GAMING PLUS' }) }
                    'Win32_OperatingSystem' { @([PSCustomObject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.26200'; BuildNumber = '26200' }) }
                    'Win32_DiskDrive' { @([PSCustomObject]@{ Model = 'Samsung SSD 990 PRO 2TB'; Size = 2000398934016 }) }
                    'Win32_NetworkAdapter' { @([PSCustomObject]@{ Name = 'Realtek Gaming 2.5GbE'; NetEnabled = $true }, [PSCustomObject]@{ Name = 'Bluetooth PAN'; NetEnabled = $false }) }
                    default { @() }
                }
            }
            Mock -ModuleName HardwareDetection Get-PhoenixTpmState { 'Present' }
            Mock -ModuleName HardwareDetection Get-PhoenixSecureBootState { 'Enabled' }
        }
    }

    It 'assembles the full hardware object from mocked system queries' {
        New-CimFixture

        $hardware = Get-PhoenixHardware

        $hardware.Cpu.Vendor | Should -Be 'AMD'
        $hardware.Cpu.Cores | Should -Be 8
        $hardware.Gpus[0].Vendor | Should -Be 'AMD'
        $hardware.MemoryGB | Should -BeGreaterThan 31
        $hardware.System.FormFactor | Should -Be 'Desktop'
        $hardware.System.IsVirtualMachine | Should -Be $false
        $hardware.Motherboard.Product | Should -Be 'B650 GAMING PLUS'
        $hardware.OperatingSystem.BuildNumber | Should -Be '26200'
        $hardware.Tpm | Should -Be 'Present'
        $hardware.SecureBoot | Should -Be 'Enabled'
        $hardware.Disks[0].SizeGB | Should -BeGreaterThan 1800
        $hardware.NetworkAdapters | Should -Contain 'Realtek Gaming 2.5GbE'
        $hardware.NetworkAdapters | Should -Not -Contain 'Bluetooth PAN'
    }

    It 'classifies laptop chassis types as Laptop' {
        New-CimFixture -ChassisTypes @(10)

        (Get-PhoenixHardware).System.FormFactor | Should -Be 'Laptop'
    }

    It 'detects a virtual machine from the system model' {
        New-CimFixture -Manufacturer 'Microsoft Corporation' -Model 'Virtual Machine'

        (Get-PhoenixHardware).System.IsVirtualMachine | Should -Be $true
    }

    It 'degrades to Unknown values, never throws, when CIM returns nothing' {
        Mock -ModuleName HardwareDetection Get-PhoenixCimInstance { @() }
        Mock -ModuleName HardwareDetection Get-PhoenixTpmState { 'Unknown' }
        Mock -ModuleName HardwareDetection Get-PhoenixSecureBootState { 'Unknown' }

        $hardware = Get-PhoenixHardware

        $hardware.Cpu.Vendor | Should -Be 'Unknown'
        $hardware.System.Manufacturer | Should -Be 'Unknown'
        $hardware.MemoryGB | Should -Be 0
    }

    It 'returns real data on this machine without throwing (integration sanity check)' {
        $hardware = Get-PhoenixHardware

        $hardware.Cpu.Name | Should -Not -BeNullOrEmpty
        $hardware.Tpm | Should -BeIn @('Present', 'Absent', 'Unknown')
        $hardware.SecureBoot | Should -BeIn @('Enabled', 'Disabled', 'NotSupported', 'Unknown')
    }
}

Describe 'Get-HardwareDetectionModuleDefinition' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/HardwareDetection/HardwareDetection.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'runs the full lifecycle and surfaces hardware items through the Details channel' {
        $definition = Get-HardwareDetectionModuleDefinition
        $health = Invoke-PhoenixModuleLifecycle @definition

        $health.Status | Should -Be 'Healthy'
        @($health.Details).Count | Should -BeGreaterOrEqual 5
        @($health.Details | Where-Object Name -eq 'CPU').Count | Should -Be 1
    }
}
