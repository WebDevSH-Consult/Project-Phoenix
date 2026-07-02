Describe 'Get-PhoenixGpuInfo / Test-PhoenixGpu' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reports PASS and the correct vendor for an AMD adapter, without assuming AMD' {
        Mock -ModuleName Validation Get-CimInstance {
            [PSCustomObject]@{ Name = 'AMD Radeon RX 7900 XT' }
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'AMD'
    }

    It 'reports PASS and the correct vendor for an NVIDIA adapter, without assuming NVIDIA' {
        Mock -ModuleName Validation Get-CimInstance {
            [PSCustomObject]@{ Name = 'NVIDIA GeForce RTX 4080' }
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'NVIDIA'
    }

    It 'reports WARN, not an error, for an unrecognised adapter vendor' {
        Mock -ModuleName Validation Get-CimInstance {
            [PSCustomObject]@{ Name = 'Some Unbranded Display Adapter' }
        }

        $result = Test-PhoenixGpu

        $result.Status | Should -Be 'WARN'
    }

    It 'reports FAIL when no GPU is detected at all' {
        Mock -ModuleName Validation Get-CimInstance { }

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
