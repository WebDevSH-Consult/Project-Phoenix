Describe 'Test-PhoenixGpu' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports PASS and the correct vendor for an AMD adapter, without assuming AMD' {
        Mock -ModuleName Validation Get-PhoenixGpuInfo {
            @([PSCustomObject]@{ Name = 'AMD Radeon RX 7900 XT'; Vendor = 'AMD' })
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'AMD'
    }

    It 'reports PASS and the correct vendor for an NVIDIA adapter, without assuming NVIDIA' {
        Mock -ModuleName Validation Get-PhoenixGpuInfo {
            @([PSCustomObject]@{ Name = 'NVIDIA GeForce RTX 4080'; Vendor = 'NVIDIA' })
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'NVIDIA'
    }

    It 'reports WARN, not an error, for an unrecognised adapter vendor' {
        Mock -ModuleName Validation Get-PhoenixGpuInfo {
            @([PSCustomObject]@{ Name = 'Some Unbranded Display Adapter'; Vendor = 'Unknown' })
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'WARN'
    }

    It 'reports FAIL when no GPU is detected at all' {
        Mock -ModuleName Validation Get-PhoenixGpuInfo { @() }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'FAIL'
    }
}

Describe 'Test-PhoenixCommandAvailable' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports PASS when the command exists' {
        $result = Test-PhoenixCommandAvailable -CommandName 'Get-Command' -DisplayName 'Get-Command'
        $result.Status | Should -Be 'PASS'
    }

    It 'reports FAIL when the command does not exist' {
        $result = Test-PhoenixCommandAvailable -CommandName 'Definitely-Not-A-Real-Command-12345' -DisplayName 'Fake'
        $result.Status | Should -Be 'FAIL'
    }
}

Describe 'Test-PhoenixAppxPackageAvailable' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
            function Get-AppxPackage { param($Name) }
        }
    }

    It 'reports PASS when the package is installed' {
        Mock -ModuleName Validation Get-AppxPackage {
            [PSCustomObject]@{ Version = '1.2.3' }
        }

        $result = Test-PhoenixAppxPackageAvailable -PackageName 'Some.Package' -DisplayName 'Some Package'

        $result.Status | Should -Be 'PASS'
    }

    It 'reports WARN, never FAIL, when the package is absent - Store packages are never assumed to exist' {
        Mock -ModuleName Validation Get-AppxPackage { }

        $result = Test-PhoenixAppxPackageAvailable -PackageName 'Some.Package' -DisplayName 'Some Package'

        $result.Status | Should -Be 'WARN'
    }
}

Describe 'Test-PhoenixPathExists' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports PASS when the path exists' {
        $existingPath = Join-Path $TestDrive 'exists.txt'
        Set-Content -Path $existingPath -Value 'x'

        $result = Test-PhoenixPathExists -Path $existingPath -DisplayName 'Fixture File'

        $result.Status | Should -Be 'PASS'
    }

    It 'reports WARN, not FAIL, when the path does not exist' {
        $missingPath = Join-Path $TestDrive 'does-not-exist.txt'

        $result = Test-PhoenixPathExists -Path $missingPath -DisplayName 'Fixture File'

        $result.Status | Should -Be 'WARN'
    }
}

Describe 'Test-PhoenixWinGetPackageInstalled' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports PASS when WinGet lists the package' {
        Mock -ModuleName Validation Invoke-PhoenixWinGetList {
            [PSCustomObject]@{ ExitCode = 0; Output = "Name  Id         Version`nSteam Valve.Steam 1.0" }
        }

        $result = Test-PhoenixWinGetPackageInstalled -PackageId 'Valve.Steam' -DisplayName 'Steam'

        $result.Status | Should -Be 'PASS'
    }

    It 'reports WARN, never FAIL, when WinGet does not list the package - never assumed to be expected' {
        Mock -ModuleName Validation Invoke-PhoenixWinGetList {
            [PSCustomObject]@{ ExitCode = 1; Output = 'No installed package found matching input criteria.' }
        }

        $result = Test-PhoenixWinGetPackageInstalled -PackageId 'Valve.Steam' -DisplayName 'Steam'

        $result.Status | Should -Be 'WARN'
    }
}

Describe 'Get-ValidationModuleDefinition' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports Warning through the lifecycle when a check fails, without throwing' {
        Mock -ModuleName Validation Invoke-PhoenixValidationReport {
            @([PSCustomObject]@{ Category = 'Windows'; Name = 'Fake'; Status = 'FAIL'; Message = 'forced failure' })
        }

        $definition = Get-ValidationModuleDefinition
        $health = Invoke-PhoenixModuleLifecycle @definition

        $health.Status | Should -Be 'Warning'
    }

    It 'reports Healthy through the lifecycle when every check passes' {
        Mock -ModuleName Validation Invoke-PhoenixValidationReport {
            @([PSCustomObject]@{ Category = 'Windows'; Name = 'Fake'; Status = 'PASS'; Message = 'ok' })
        }

        $definition = Get-ValidationModuleDefinition
        $health = Invoke-PhoenixModuleLifecycle @definition

        $health.Status | Should -Be 'Healthy'
    }
}

Describe 'Installer preflight (ADR 0012)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'Test-PhoenixPendingReboot FAILs when Component Based Servicing signals a reboot' {
        Mock -ModuleName Validation Test-PhoenixPreflightRegistryKey {
            param($Path)
            return ($Path -match 'Component Based Servicing')
        }

        $result = Test-PhoenixPendingReboot

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match 'Component Based Servicing'
        $result.Message | Should -Match 'Restart'
    }

    It 'Test-PhoenixPendingReboot FAILs when Windows Update signals a reboot' {
        Mock -ModuleName Validation Test-PhoenixPreflightRegistryKey {
            param($Path)
            return ($Path -match 'RebootRequired')
        }

        (Test-PhoenixPendingReboot).Status | Should -Be 'FAIL'
    }

    It 'Test-PhoenixPendingReboot PASSes when neither signal is present' {
        Mock -ModuleName Validation Test-PhoenixPreflightRegistryKey { $false }

        (Test-PhoenixPendingReboot).Status | Should -Be 'PASS'
    }

    It 'Test-PhoenixPendingFileOperations FAILs with count and components when operations are pending' {
        Mock -ModuleName Validation Get-PhoenixPreflightRegistryValue {
            @('\??\C:\Program Files\OneDrive\old.dll', '', '\??\C:\Windows\Temp\chrome_update.exe', '')
        }

        $result = Test-PhoenixPendingFileOperations

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match '2 pending'
        $result.Message | Should -Match 'old.dll'
        $result.Message | Should -Match 'Restart'
    }

    It 'Test-PhoenixPendingFileOperations PASSes when the value is absent' {
        Mock -ModuleName Validation Get-PhoenixPreflightRegistryValue { $null }

        (Test-PhoenixPendingFileOperations).Status | Should -Be 'PASS'
    }

    It 'Test-PhoenixActiveInstaller FAILs when the MSI mutex is held' {
        Mock -ModuleName Validation Test-PhoenixMsiMutexHeld { $true }

        $result = Test-PhoenixActiveInstaller

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match 'in progress'
    }

    It 'Test-PhoenixActiveInstaller PASSes when no installer is running' {
        Mock -ModuleName Validation Test-PhoenixMsiMutexHeld { $false }

        (Test-PhoenixActiveInstaller).Status | Should -Be 'PASS'
    }

    It 'Get-PhoenixPreflightState is Safe only when every check passes' {
        Mock -ModuleName Validation Test-PhoenixPreflightRegistryKey { $false }
        Mock -ModuleName Validation Get-PhoenixPreflightRegistryValue { $null }
        Mock -ModuleName Validation Test-PhoenixMsiMutexHeld { $false }

        $state = Get-PhoenixPreflightState

        $state.Safe | Should -Be $true
        @($state.Results).Count | Should -Be 3
    }

    It 'Get-PhoenixPreflightState is unsafe when any check fails' {
        Mock -ModuleName Validation Test-PhoenixPreflightRegistryKey { $false }
        Mock -ModuleName Validation Get-PhoenixPreflightRegistryValue { @('\??\C:\pending.dll') }
        Mock -ModuleName Validation Test-PhoenixMsiMutexHeld { $false }

        (Get-PhoenixPreflightState).Safe | Should -Be $false
    }
}
