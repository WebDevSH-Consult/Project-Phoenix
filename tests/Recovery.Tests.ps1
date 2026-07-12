Describe 'Undo-PhoenixSettingChange (ADR 0015)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Recovery/Recovery.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'restores a previous value and verifies, reporting PASS' {
        $script:RegState = 1
        Mock -ModuleName Recovery Set-PhoenixRegistryValue { $script:RegState = 0 }
        Mock -ModuleName Recovery Get-PhoenixRegistryValue { $script:RegState }

        $result = Undo-PhoenixSettingChange -Name 'Dark mode' -Path 'HKCU:\Software\T' -ValueName 'V' -ValueKind 'DWord' -PreviousValue 0

        $result.Category | Should -Be 'Rollback'
        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'restored'
    }

    It 'removes the value (and verifies) when the previous value was unset' {
        $script:Present = $true
        Mock -ModuleName Recovery Remove-PhoenixRegistryValue { $script:Present = $false }
        Mock -ModuleName Recovery Get-PhoenixRegistryValue { if ($script:Present) { 1 } else { $null } }

        $result = Undo-PhoenixSettingChange -Name 'Introduced' -Path 'HKCU:\Software\T' -ValueName 'V' -ValueKind 'DWord' -PreviousValue $null

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'removed'
        Should -Invoke -ModuleName Recovery Remove-PhoenixRegistryValue -Times 1
    }

    It 'reports FAIL when the restore does not take effect' {
        Mock -ModuleName Recovery Set-PhoenixRegistryValue { }
        Mock -ModuleName Recovery Get-PhoenixRegistryValue { 99 }

        (Undo-PhoenixSettingChange -Name 'V' -Path 'HKCU:\Software\T' -ValueName 'V' -ValueKind 'DWord' -PreviousValue 0).Status | Should -Be 'FAIL'
    }

    It 'reports FAIL (not a raw exception) when the registry write throws' {
        Mock -ModuleName Recovery Set-PhoenixRegistryValue { throw 'access denied' }
        Mock -ModuleName Recovery Get-PhoenixRegistryValue { 1 }

        $result = Undo-PhoenixSettingChange -Name 'V' -Path 'HKCU:\Software\T' -ValueName 'V' -ValueKind 'DWord' -PreviousValue 0

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match 'access denied'
    }
}

Describe 'Undo-PhoenixApplicationInstall (ADR 0015)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Recovery/Recovery.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'uninstalls via the Installer and reports the outcome as a Rollback result' {
        Mock -ModuleName Recovery Uninstall-PhoenixApplication {
            [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'PASS'; Message = 'Uninstalled successfully.' }
        }

        $result = Undo-PhoenixApplicationInstall -Manifest ([PSCustomObject]@{ Name = 'Git'; Installer = 'Winget'; Id = 'Git.Git' })

        $result.Category | Should -Be 'Rollback'
        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'Install rollback'
    }

    It 'propagates a FAIL from the uninstall' {
        Mock -ModuleName Recovery Uninstall-PhoenixApplication {
            [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'FAIL'; Message = 'Uninstall did not remove the application.' }
        }

        (Undo-PhoenixApplicationInstall -Manifest ([PSCustomObject]@{ Name = 'Git'; Installer = 'Winget'; Id = 'Git.Git' })).Status | Should -Be 'FAIL'
    }
}

Describe 'Get-PhoenixRollbackPlan (ADR 0015)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Recovery/Recovery.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        $script:SettingManifests = @(
            [PSCustomObject]@{ Name = 'Dark mode'; Path = 'HKCU:\Software\Themes'; ValueName = 'AppsUseLightTheme'; ValueKind = 'DWord' }
        )
        $script:AppManifests = @(
            [PSCustomObject]@{ Name = 'Git'; Installer = 'Winget'; Id = 'Git.Git' }
        )
    }

    It 'includes only confirmed (Changed) changes, and orders applications before settings' {
        $report = [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{ Module = 'WindowsConfig'; Details = @(
                    [PSCustomObject]@{ Category = 'Setting'; Name = 'Dark mode'; Status = 'PASS'; PreviousValue = 1; Changed = $true }
                    [PSCustomObject]@{ Category = 'Setting'; Name = 'Show hidden'; Status = 'PASS'; PreviousValue = 0; Changed = $false }
                ) }
                [PSCustomObject]@{ Module = 'Installer'; Details = @(
                    [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'PASS'; Changed = $true }
                ) }
            )
        }

        $plan = Get-PhoenixRollbackPlan -Report $report -SettingManifests $script:SettingManifests -ApplicationManifests $script:AppManifests

        $plan.Count | Should -Be 2
        $plan[0].Type | Should -Be 'Application'
        $plan[0].Name | Should -Be 'Git'
        $plan[1].Type | Should -Be 'Setting'
        $plan[1].Path | Should -Be 'HKCU:\Software\Themes'
        $plan[1].PreviousValue | Should -Be 1
    }

    It 'skips a changed detail whose manifest is missing, without failing the plan' {
        $report = [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{ Module = 'WindowsConfig'; Details = @(
                    [PSCustomObject]@{ Category = 'Setting'; Name = 'Ghost setting'; Status = 'PASS'; PreviousValue = 1; Changed = $true }
                ) }
            )
        }

        $plan = Get-PhoenixRollbackPlan -Report $report -SettingManifests $script:SettingManifests -ApplicationManifests $script:AppManifests

        $plan.Count | Should -Be 0
    }

    It 'returns an empty plan when nothing changed' {
        $report = [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{ Module = 'WindowsConfig'; Details = @(
                    [PSCustomObject]@{ Category = 'Setting'; Name = 'Dark mode'; Status = 'PASS'; PreviousValue = 0; Changed = $false }
                ) }
            )
        }

        @(Get-PhoenixRollbackPlan -Report $report -SettingManifests $script:SettingManifests -ApplicationManifests $script:AppManifests).Count | Should -Be 0
    }
}

Describe 'Invoke-PhoenixRollback (ADR 0015)' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Recovery/Recovery.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'reads a report, builds a plan, and reverses each change' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $reportsDir = Join-Path $root 'reports'
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
        $report = [PSCustomObject]@{
            Modules = @(
                [PSCustomObject]@{ Module = 'WindowsConfig'; Details = @([PSCustomObject]@{ Category = 'Setting'; Name = 'Dark mode'; Status = 'PASS'; PreviousValue = 1; Changed = $true }) }
                [PSCustomObject]@{ Module = 'Installer'; Details = @([PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'PASS'; Changed = $true }) }
            )
        }
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $reportsDir 'deployment-report-20260101-000000.json')

        Mock -ModuleName Recovery Get-PhoenixSettingManifest { @([PSCustomObject]@{ Name = 'Dark mode'; Path = 'HKCU:\Software\Themes'; ValueName = 'AppsUseLightTheme'; ValueKind = 'DWord' }) }
        Mock -ModuleName Recovery Get-PhoenixApplicationManifest { @([PSCustomObject]@{ Name = 'Git'; Installer = 'Winget'; Id = 'Git.Git' }) }
        Mock -ModuleName Recovery Undo-PhoenixSettingChange { [PSCustomObject]@{ Category = 'Rollback'; Name = 'Dark mode'; Status = 'PASS'; Message = 'restored' } }
        Mock -ModuleName Recovery Undo-PhoenixApplicationInstall { [PSCustomObject]@{ Category = 'Rollback'; Name = 'Git'; Status = 'PASS'; Message = 'uninstalled' } }

        $results = Invoke-PhoenixRollback -RootPath $root

        $results.Count | Should -Be 2
        Should -Invoke -ModuleName Recovery Undo-PhoenixApplicationInstall -Times 1
        Should -Invoke -ModuleName Recovery Undo-PhoenixSettingChange -Times 1
    }

    It 'throws a clean error when no report exists' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'reports') -Force | Out-Null

        { Invoke-PhoenixRollback -RootPath $root } | Should -Throw '*No deployment report*'
    }
}
