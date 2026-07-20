Describe 'Get-PhoenixState (ADR 0018)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/StateEngine/StateEngine.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-AppManifest { param([string]$Name) [PSCustomObject]@{ Name = $Name; Installer = 'Winget'; Id = "$Name.Id"; ConfigFlag = "apps.$Name" } }
        function New-SettingManifest { param([string]$Name) [PSCustomObject]@{ Name = $Name; Type = 'Registry'; ConfigFlag = "windows.$Name" } }
    }

    BeforeEach {
        # In scope: one app, one setting. State/predicates are mocked so the
        # real status logic in Get-PhoenixState is what's under test.
        Mock -ModuleName StateEngine Get-PhoenixConfiguration { [PSCustomObject]@{} }
        Mock -ModuleName StateEngine Get-PhoenixConfigValue { $true }
        Mock -ModuleName StateEngine Get-PhoenixApplicationManifest { @(New-AppManifest -Name 'Discord') }
        Mock -ModuleName StateEngine Get-PhoenixSettingManifest { @(New-SettingManifest -Name 'DarkMode') }
        Mock -ModuleName StateEngine Test-PhoenixApplicationSatisfied { $true }
        Mock -ModuleName StateEngine Test-PhoenixApplicationOutdated { $false }
        Mock -ModuleName StateEngine Test-PhoenixSettingApplied { $true }
    }

    It 'reports an installed, current application as Present' {
        $state = Get-PhoenixState -RootPath $TestDrive
        ($state.Applications | Where-Object Name -eq 'Discord').Status | Should -Be 'Present'
    }

    It 'reports a declared-but-uninstalled application as Missing, without checking version' {
        Mock -ModuleName StateEngine Test-PhoenixApplicationSatisfied { $false }
        Mock -ModuleName StateEngine Test-PhoenixApplicationOutdated { throw 'should not check version of a missing app' }

        ($state = Get-PhoenixState -RootPath $TestDrive).Applications[0].Status | Should -Be 'Missing'
        Should -Invoke -ModuleName StateEngine Test-PhoenixApplicationOutdated -Times 0
    }

    It 'reports an installed application with an available upgrade as Outdated' {
        Mock -ModuleName StateEngine Test-PhoenixApplicationOutdated { $true }
        ($state = Get-PhoenixState -RootPath $TestDrive).Applications[0].Status | Should -Be 'Outdated'
    }

    It 'reports a setting matching its desired value as Applied' {
        (Get-PhoenixState -RootPath $TestDrive).Settings[0].Status | Should -Be 'Applied'
    }

    It 'reports a setting whose value has changed as Modified' {
        Mock -ModuleName StateEngine Test-PhoenixSettingApplied { $false }
        (Get-PhoenixState -RootPath $TestDrive).Settings[0].Status | Should -Be 'Modified'
    }

    It 'excludes candidates the configuration has not enabled' {
        Mock -ModuleName StateEngine Get-PhoenixConfigValue { $false }
        $state = Get-PhoenixState -RootPath $TestDrive
        $state.Applications.Count | Should -Be 0
        $state.Settings.Count | Should -Be 0
    }

    It 'scopes applications to a named profile' {
        Mock -ModuleName StateEngine Get-PhoenixProfile { [PSCustomObject]@{ Name = 'Gaming'; Applications = @('Discord') } }
        Mock -ModuleName StateEngine Expand-PhoenixProfileApplications { @(New-AppManifest -Name 'Discord') }

        $state = Get-PhoenixState -RootPath $TestDrive -ProfileName 'Gaming'
        $state.Scope | Should -Be 'Profile: Gaming'
        Should -Invoke -ModuleName StateEngine Expand-PhoenixProfileApplications -Times 1
    }

    It 'carries the manifest through so a later repair can act on it' {
        (Get-PhoenixState -RootPath $TestDrive).Applications[0].Manifest.Id | Should -Be 'Discord.Id'
    }
}

Describe 'Compare-PhoenixState (ADR 0018)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/StateEngine/StateEngine.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-State {
            param([object[]]$Applications = @(), [object[]]$Settings = @())
            [PSCustomObject]@{ Timestamp = 'now'; ComputerName = 'TESTPC'; Scope = 'Configuration'; Applications = @($Applications); Settings = @($Settings) }
        }
    }

    It 'returns no drift when everything conforms' {
        $state = New-State -Applications @([PSCustomObject]@{ Category = 'Application'; Name = 'Discord'; Status = 'Present'; Manifest = $null }) `
            -Settings @([PSCustomObject]@{ Category = 'Setting'; Name = 'DarkMode'; Status = 'Applied'; Manifest = $null })

        $drift = Compare-PhoenixState -State $state
        $drift.InDrift | Should -BeFalse
        $drift.Drift.Count | Should -Be 0
    }

    It 'includes only non-conforming items, each tagged with its drift type' {
        $state = New-State -Applications @(
            [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Missing'; Manifest = [PSCustomObject]@{ Name = 'Git' } }
            [PSCustomObject]@{ Category = 'Application'; Name = 'Discord'; Status = 'Present'; Manifest = $null }
            [PSCustomObject]@{ Category = 'Application'; Name = 'Steam'; Status = 'Outdated'; Manifest = $null }
        ) -Settings @(
            [PSCustomObject]@{ Category = 'Setting'; Name = 'DarkMode'; Status = 'Modified'; Manifest = $null }
            [PSCustomObject]@{ Category = 'Setting'; Name = 'HiddenFiles'; Status = 'Applied'; Manifest = $null }
        )

        $drift = Compare-PhoenixState -State $state

        $drift.InDrift | Should -BeTrue
        $drift.Drift.Count | Should -Be 3
        ($drift.Drift | Where-Object Name -eq 'Discord') | Should -BeNullOrEmpty
        ($drift.Drift | Where-Object Name -eq 'Git').DriftType | Should -Be 'Missing'
        ($drift.Drift | Where-Object Name -eq 'Steam').DriftType | Should -Be 'Outdated'
        ($drift.Drift | Where-Object Name -eq 'DarkMode').DriftType | Should -Be 'Modified'
    }

    It 'summarises drift counts by type' {
        $state = New-State -Applications @(
            [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Missing'; Manifest = $null }
            [PSCustomObject]@{ Category = 'Application'; Name = 'Steam'; Status = 'Outdated'; Manifest = $null }
        ) -Settings @(
            [PSCustomObject]@{ Category = 'Setting'; Name = 'DarkMode'; Status = 'Modified'; Manifest = $null }
        )

        $s = (Compare-PhoenixState -State $state).Summary
        $s.Missing | Should -Be 1
        $s.Outdated | Should -Be 1
        $s.Modified | Should -Be 1
        $s.Total | Should -Be 3
    }

    It 'preserves the manifest on each drift entry for repair' {
        $state = New-State -Applications @([PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Missing'; Manifest = [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git' } })
        (Compare-PhoenixState -State $state).Drift[0].Manifest.Id | Should -Be 'Git.Git'
    }
}

Describe 'Invoke-PhoenixAudit (ADR 0018)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/StateEngine/StateEngine.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'writes a timestamped drift artifact and returns the drift object' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            [PSCustomObject]@{
                Timestamp = 'now'; ComputerName = 'TESTPC'; Scope = 'Configuration'
                Applications = @([PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Missing'; Manifest = $null })
                Settings     = @([PSCustomObject]@{ Category = 'Setting'; Name = 'DarkMode'; Status = 'Applied'; Manifest = $null })
            }
        }
        $root = Join-Path $TestDrive ([guid]::NewGuid())

        $drift = Invoke-PhoenixAudit -RootPath $root

        $drift.InDrift | Should -BeTrue
        $drift.Summary.Missing | Should -Be 1
        $auditFile = Get-ChildItem -LiteralPath (Join-Path $root 'audits') -Filter 'drift-audit-*.json'
        $auditFile | Should -Not -BeNullOrEmpty
        (Get-Content -LiteralPath $auditFile.FullName -Raw | ConvertFrom-Json).Summary.Total | Should -Be 1
    }

    It 'reports and records no drift when the machine conforms' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            [PSCustomObject]@{
                Timestamp = 'now'; ComputerName = 'TESTPC'; Scope = 'Configuration'
                Applications = @([PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Present'; Manifest = $null })
                Settings     = @()
            }
        }
        $root = Join-Path $TestDrive ([guid]::NewGuid())

        (Invoke-PhoenixAudit -RootPath $root).InDrift | Should -BeFalse
    }
}

Describe 'Invoke-PhoenixRepair (ADR 0018 slice 2)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/StateEngine/StateEngine.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-DriftState {
            param([object[]]$Applications = @(), [object[]]$Settings = @())
            [PSCustomObject]@{ Timestamp = 'now'; ComputerName = 'TESTPC'; Scope = 'Configuration'; Applications = @($Applications); Settings = @($Settings) }
        }
        function New-MissingApp { param([string]$Name) [PSCustomObject]@{ Category = 'Application'; Name = $Name; Status = 'Missing'; Manifest = [PSCustomObject]@{ Name = $Name; Installer = 'Winget'; Id = "$Name.Id" } } }
        function New-OutdatedApp { param([string]$Name) [PSCustomObject]@{ Category = 'Application'; Name = $Name; Status = 'Outdated'; Manifest = [PSCustomObject]@{ Name = $Name; Installer = 'Winget'; Id = "$Name.Id" } } }
        function New-ModifiedSetting { param([string]$Name) [PSCustomObject]@{ Category = 'Setting'; Name = $Name; Status = 'Modified'; Manifest = [PSCustomObject]@{ Name = $Name; Type = 'Registry' } } }
    }

    BeforeEach {
        Mock -ModuleName StateEngine Get-PhoenixPreflightState { [PSCustomObject]@{ Safe = $true; Results = @() } }
        Mock -ModuleName StateEngine Set-PhoenixSetting { [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Applied'; PreviousValue = 0; Changed = $true } }
        Mock -ModuleName StateEngine Install-PhoenixApplication { [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Installed'; Changed = $true } }
        Mock -ModuleName StateEngine Update-PhoenixApplication { [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Upgraded' } }
        Mock -ModuleName StateEngine Invoke-PhoenixRollbackFromResults { @() }
    }

    It 'repairs only the drifted items, leaving conforming ones untouched' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @(
                (New-MissingApp -Name 'Git')
                [PSCustomObject]@{ Category = 'Application'; Name = 'Discord'; Status = 'Present'; Manifest = $null }
            ) -Settings @(
                (New-ModifiedSetting -Name 'DarkMode')
                [PSCustomObject]@{ Category = 'Setting'; Name = 'HiddenFiles'; Status = 'Applied'; Manifest = $null }
            )
        }

        $results = Invoke-PhoenixRepair -RootPath $TestDrive

        $results.Count | Should -Be 2
        $results.Name | Should -Contain 'Git'
        $results.Name | Should -Contain 'DarkMode'
        $results.Name | Should -Not -Contain 'Discord'
        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 1
        Should -Invoke -ModuleName StateEngine Set-PhoenixSetting -Times 1
    }

    It 'installs a Missing application and upgrades an Outdated one' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @((New-MissingApp -Name 'Git'), (New-OutdatedApp -Name 'Steam'))
        }

        $null = Invoke-PhoenixRepair -RootPath $TestDrive

        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 1
        Should -Invoke -ModuleName StateEngine Update-PhoenixApplication -Times 1
    }

    It 'repairs settings before applications (forward deployment order)' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @((New-MissingApp -Name 'Git')) -Settings @((New-ModifiedSetting -Name 'DarkMode'))
        }

        $results = Invoke-PhoenixRepair -RootPath $TestDrive

        $results[0].Category | Should -Be 'Setting'
        $results[1].Category | Should -Be 'Application'
    }

    It 'does nothing when there is no drift' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @([PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'Present'; Manifest = $null })
        }

        @(Invoke-PhoenixRepair -RootPath $TestDrive).Count | Should -Be 0
        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 0
    }

    It 'previews without invoking any backend under -DryRun' {
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @((New-MissingApp -Name 'Git')) -Settings @((New-ModifiedSetting -Name 'DarkMode'))
        }

        $results = Invoke-PhoenixRepair -RootPath $TestDrive -DryRun

        $results.Count | Should -Be 2
        @($results | Where-Object Status -eq 'WARN').Count | Should -Be 2
        $results[1].Message | Should -Match 'would install'
        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 0
        Should -Invoke -ModuleName StateEngine Set-PhoenixSetting -Times 0
    }

    It 'blocks application repairs when preflight is unsafe, but still repairs settings' {
        Mock -ModuleName StateEngine Get-PhoenixPreflightState {
            [PSCustomObject]@{ Safe = $false; Results = @([PSCustomObject]@{ Name = 'PendingReboot'; Status = 'FAIL' }) }
        }
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @((New-MissingApp -Name 'Git')) -Settings @((New-ModifiedSetting -Name 'DarkMode'))
        }

        $results = Invoke-PhoenixRepair -RootPath $TestDrive

        ($results | Where-Object Name -eq 'Git').Status | Should -Be 'WARN'
        ($results | Where-Object Name -eq 'Git').Message | Should -Match 'PendingReboot'
        ($results | Where-Object Name -eq 'DarkMode').Status | Should -Be 'PASS'
        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 0
        Should -Invoke -ModuleName StateEngine Set-PhoenixSetting -Times 1
    }

    It 'proceeds with application repairs when preflight is bypassed' {
        Mock -ModuleName StateEngine Get-PhoenixPreflightState { throw 'should not be called' }
        Mock -ModuleName StateEngine Get-PhoenixState { New-DriftState -Applications @((New-MissingApp -Name 'Git')) }

        $null = Invoke-PhoenixRepair -RootPath $TestDrive -SkipPreflight

        Should -Invoke -ModuleName StateEngine Install-PhoenixApplication -Times 1
    }

    It 'reverses the repairs that changed when -Transactional and a repair fails' {
        Mock -ModuleName StateEngine Install-PhoenixApplication { [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'FAIL'; Message = 'install failed'; Changed = $false } }
        Mock -ModuleName StateEngine Get-PhoenixState {
            New-DriftState -Applications @((New-MissingApp -Name 'Git')) -Settings @((New-ModifiedSetting -Name 'DarkMode'))
        }

        $null = Invoke-PhoenixRepair -RootPath $TestDrive -Transactional

        Should -Invoke -ModuleName StateEngine Invoke-PhoenixRollbackFromResults -Times 1
    }

    It 'does not reverse anything when every repair succeeds' {
        Mock -ModuleName StateEngine Get-PhoenixState { New-DriftState -Settings @((New-ModifiedSetting -Name 'DarkMode')) }

        $null = Invoke-PhoenixRepair -RootPath $TestDrive -Transactional

        Should -Invoke -ModuleName StateEngine Invoke-PhoenixRollbackFromResults -Times 0
    }
}
