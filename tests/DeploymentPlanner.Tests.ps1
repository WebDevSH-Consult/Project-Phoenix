Describe 'New-PhoenixDeploymentPlan' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/DeploymentPlanner/DeploymentPlanner.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        # Fixture manifests. Config gating and state are mocked, so the real
        # decision logic in New-PhoenixDeploymentPlan is what's under test.
        function New-AppManifest {
            param([string]$Name)
            [PSCustomObject]@{ Name = $Name; Installer = 'Winget'; ConfigFlag = "apps.$Name"; Validate = @() }
        }
        function New-SettingManifest {
            param([string]$Name, [bool]$RequiresElevation = $false)
            [PSCustomObject]@{ Name = $Name; Type = 'Registry'; ConfigFlag = "windows.$Name"; RequiresElevation = $RequiresElevation }
        }

        $script:Hardware = [PSCustomObject]@{
            Cpu      = [PSCustomObject]@{ Name = 'Test CPU'; Vendor = 'AMD' }
            Gpus     = @([PSCustomObject]@{ Name = 'Test GPU'; Vendor = 'AMD' })
            MemoryGB = 32
            System   = [PSCustomObject]@{ FormFactor = 'Desktop' }
        }
    }

    BeforeEach {
        # Defaults: everything in scope, nothing installed/applied, safe, elevated.
        Mock -ModuleName DeploymentPlanner Get-PhoenixConfiguration { [PSCustomObject]@{} }
        Mock -ModuleName DeploymentPlanner Get-PhoenixConfigValue { $true }
        Mock -ModuleName DeploymentPlanner Get-PhoenixHardware { $script:Hardware }
        Mock -ModuleName DeploymentPlanner Test-PhoenixElevated { $true }
        Mock -ModuleName DeploymentPlanner Get-PhoenixPreflightState { [PSCustomObject]@{ Safe = $true; Results = @() } }
        Mock -ModuleName DeploymentPlanner Get-PhoenixApplicationManifest { @(New-AppManifest -Name 'Discord') }
        Mock -ModuleName DeploymentPlanner Get-PhoenixSettingManifest { @(New-SettingManifest -Name 'DarkMode') }
        Mock -ModuleName DeploymentPlanner Test-PhoenixApplicationSatisfied { $false }
        Mock -ModuleName DeploymentPlanner Test-PhoenixSettingApplied { $false }
    }

    It 'plans an install for an application that is not satisfied and passes preflight' {
        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'Discord'
        $action.Category | Should -Be 'Application'
        $action.Action | Should -Be 'Install'
        $action.EstimatedSeconds | Should -BeGreaterThan 0
    }

    It 'skips an application that is already satisfied' {
        Mock -ModuleName DeploymentPlanner Test-PhoenixApplicationSatisfied { $true }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        ($plan.Actions | Where-Object Name -eq 'Discord').Action | Should -Be 'Skip'
        $plan.Summary.Skip | Should -Be 1
        $plan.Summary.Changing | Should -Be 1  # the setting still applies
    }

    It 'defers an application install when preflight is unsafe, naming the reason' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixPreflightState {
            [PSCustomObject]@{ Safe = $false; Results = @([PSCustomObject]@{ Name = 'PendingReboot'; Status = 'FAIL' }) }
        }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'Discord'
        $action.Action | Should -Be 'Defer'
        $action.Reason | Should -BeLike '*PendingReboot*'
    }

    It 'applies a setting that is not in the desired state' {
        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'DarkMode'
        $action.Category | Should -Be 'Setting'
        $action.Action | Should -Be 'Apply'
    }

    It 'skips a setting already in the desired state' {
        Mock -ModuleName DeploymentPlanner Test-PhoenixSettingApplied { $true }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        ($plan.Actions | Where-Object Name -eq 'DarkMode').Action | Should -Be 'Skip'
    }

    It 'defers an elevation-requiring setting when the process is not elevated' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixSettingManifest { @(New-SettingManifest -Name 'SecureBoot' -RequiresElevation $true) }
        Mock -ModuleName DeploymentPlanner Test-PhoenixElevated { $false }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'SecureBoot'
        $action.Action | Should -Be 'Defer'
        $action.Reason | Should -BeLike '*elevation*'
    }

    It 'marks an elevation-requiring setting apply as Medium risk when elevated' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixSettingManifest { @(New-SettingManifest -Name 'SecureBoot' -RequiresElevation $true) }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'SecureBoot'
        $action.Action | Should -Be 'Apply'
        $action.Risk | Should -Be 'Medium'
        $plan.Summary.Risk | Should -Be 'Medium'
    }

    It 'excludes candidates the configuration has not enabled' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixConfigValue { $false }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $plan.Actions.Count | Should -Be 0
        $plan.Summary.Changing | Should -Be 0
    }

    It 'reports the detected machine in the plan header' {
        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $plan.Machine.Cpu | Should -BeLike '*Test CPU*AMD*'
        $plan.Machine.MemoryGB | Should -Be 32
        $plan.Machine.FormFactor | Should -Be 'Desktop'
    }

    It 'summarises counts and estimated time' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixApplicationManifest { @(New-AppManifest -Name 'Discord'), (New-AppManifest -Name 'OBS') }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $plan.Summary.Install | Should -Be 2
        $plan.Summary.Apply | Should -Be 1
        $plan.Summary.Changing | Should -Be 3
        $plan.Summary.EstimatedMinutes | Should -BeGreaterThan 0
    }

    Context 'profile scope' {
        It 'plans over the profile applications, not the whole configuration' {
            Mock -ModuleName DeploymentPlanner Get-PhoenixProfile { [PSCustomObject]@{ Name = 'Gaming'; Applications = @('Discord') } }
            Mock -ModuleName DeploymentPlanner Expand-PhoenixProfileApplications { @(New-AppManifest -Name 'Discord') }

            $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive -ProfileName 'Gaming'

            $plan.Scope | Should -Be 'Profile: Gaming'
            Should -Invoke -ModuleName DeploymentPlanner Expand-PhoenixProfileApplications -Times 1
            ($plan.Actions | Where-Object Category -eq 'Application').Name | Should -Be 'Discord'
        }
    }
}

Describe 'Export-PhoenixDeploymentPlan / Get-PhoenixDeploymentPlan' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/DeploymentPlanner/DeploymentPlanner.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'writes a timestamped JSON plan and reads it back' {
        $plan = [PSCustomObject]@{ Scope = 'Configuration'; Actions = @([PSCustomObject]@{ Name = 'Discord'; Action = 'Install' }) }
        $root = Join-Path $TestDrive ([guid]::NewGuid())

        $path = Export-PhoenixDeploymentPlan -Plan $plan -RootPath $root

        $path | Should -Match 'deployment-plan-\d{8}-\d{6}\.json$'
        Test-Path -LiteralPath $path | Should -BeTrue

        $loaded = Get-PhoenixDeploymentPlan -RootPath $root
        $loaded.Scope | Should -Be 'Configuration'
        $loaded.Actions[0].Name | Should -Be 'Discord'
    }

    It 'loads an explicit plan path when given one' {
        $plan = [PSCustomObject]@{ Scope = 'Profile: Gaming' }
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $path = Export-PhoenixDeploymentPlan -Plan $plan -RootPath $root

        (Get-PhoenixDeploymentPlan -RootPath $root -Path $path).Scope | Should -Be 'Profile: Gaming'
    }

    It 'throws when no plan exists to load' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null

        { Get-PhoenixDeploymentPlan -RootPath $root } | Should -Throw '*No deployment plan*'
    }
}
