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
