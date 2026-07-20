Describe 'New-PhoenixDeploymentPlan' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/DeploymentPlanner/DeploymentPlanner.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        # Since ADR 0018 the planner consumes the State Engine, so the mock
        # seam is Get-PhoenixState. Scoping itself is the State Engine's
        # concern and is covered by its own tests.
        function New-State {
            param([object[]]$Applications = @(), [object[]]$Settings = @(), [string]$Scope = 'Configuration')
            [PSCustomObject]@{ Timestamp = 'now'; ComputerName = 'TESTPC'; Scope = $Scope; Applications = @($Applications); Settings = @($Settings) }
        }
        function New-AppItem {
            param([string]$Name, [string]$Status)
            [PSCustomObject]@{ Category = 'Application'; Name = $Name; Status = $Status; Manifest = [PSCustomObject]@{ Name = $Name; Installer = 'Winget'; Id = "$Name.Id" } }
        }
        function New-SettingItem {
            param([string]$Name, [string]$Status, [bool]$RequiresElevation = $false)
            [PSCustomObject]@{ Category = 'Setting'; Name = $Name; Status = $Status; Manifest = [PSCustomObject]@{ Name = $Name; Type = 'Registry'; RequiresElevation = $RequiresElevation } }
        }

        $script:Hardware = [PSCustomObject]@{
            Cpu      = [PSCustomObject]@{ Name = 'Test CPU'; Vendor = 'AMD' }
            Gpus     = @([PSCustomObject]@{ Name = 'Test GPU'; Vendor = 'AMD' })
            MemoryGB = 32
            System   = [PSCustomObject]@{ FormFactor = 'Desktop' }
        }
    }

    BeforeEach {
        Mock -ModuleName DeploymentPlanner Get-PhoenixHardware { $script:Hardware }
        Mock -ModuleName DeploymentPlanner Test-PhoenixElevated { $true }
        Mock -ModuleName DeploymentPlanner Get-PhoenixPreflightState { [PSCustomObject]@{ Safe = $true; Results = @() } }
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Applications @((New-AppItem -Name 'Discord' -Status 'Missing')) -Settings @((New-SettingItem -Name 'DarkMode' -Status 'Modified'))
        }
    }

    It 'plans an install for a missing application when preflight is safe' {
        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $action = $plan.Actions | Where-Object Name -eq 'Discord'
        $action.Category | Should -Be 'Application'
        $action.Action | Should -Be 'Install'
        $action.EstimatedSeconds | Should -BeGreaterThan 0
    }

    It 'skips an application that is already installed' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Applications @((New-AppItem -Name 'Discord' -Status 'Present'))
        }

        ($plan = New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions[0].Action | Should -Be 'Skip'
        $plan.Summary.Changing | Should -Be 0
    }

    It 'skips an installed-but-outdated application - an orchestrated run never upgrades' {
        # Fidelity (ADR 0016): the plan must match a real run. Upgrades belong
        # to Invoke-PhoenixRepair, not deployment.
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Applications @((New-AppItem -Name 'Steam' -Status 'Outdated'))
        }

        $action = (New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions[0]
        $action.Action | Should -Be 'Skip'
        $action.Reason | Should -Be 'Already installed.'
    }

    It 'requests state without the version check (a plan would not act on it)' {
        $null = New-PhoenixDeploymentPlan -RootPath $TestDrive

        Should -Invoke -ModuleName DeploymentPlanner Get-PhoenixState -Times 1 -ParameterFilter { $SkipVersionCheck }
    }

    It 'defers an application install when preflight is unsafe, naming the reason' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixPreflightState {
            [PSCustomObject]@{ Safe = $false; Results = @([PSCustomObject]@{ Name = 'PendingReboot'; Status = 'FAIL' }) }
        }

        $action = (New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions | Where-Object Name -eq 'Discord'
        $action.Action | Should -Be 'Defer'
        $action.Reason | Should -BeLike '*PendingReboot*'
    }

    It 'applies a setting that is not in the desired state' {
        $action = (New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions | Where-Object Name -eq 'DarkMode'
        $action.Category | Should -Be 'Setting'
        $action.Action | Should -Be 'Apply'
    }

    It 'skips a setting already in the desired state' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Settings @((New-SettingItem -Name 'DarkMode' -Status 'Applied'))
        }

        (New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions[0].Action | Should -Be 'Skip'
    }

    It 'defers an elevation-requiring setting when the process is not elevated' {
        Mock -ModuleName DeploymentPlanner Test-PhoenixElevated { $false }
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Settings @((New-SettingItem -Name 'Telemetry' -Status 'Modified' -RequiresElevation $true))
        }

        $action = (New-PhoenixDeploymentPlan -RootPath $TestDrive).Actions[0]
        $action.Action | Should -Be 'Defer'
        $action.Reason | Should -BeLike '*elevation*'
    }

    It 'marks an elevation-requiring setting apply as Medium risk when elevated' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Settings @((New-SettingItem -Name 'Telemetry' -Status 'Modified' -RequiresElevation $true))
        }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive
        $plan.Actions[0].Action | Should -Be 'Apply'
        $plan.Actions[0].Risk | Should -Be 'Medium'
        $plan.Summary.Risk | Should -Be 'Medium'
    }

    It 'plans nothing when nothing is in scope' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixState { New-State }

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

    It 'orders settings before applications and summarises counts and estimated time' {
        Mock -ModuleName DeploymentPlanner Get-PhoenixState {
            New-State -Applications @((New-AppItem -Name 'Discord' -Status 'Missing'), (New-AppItem -Name 'OBS' -Status 'Missing')) `
                -Settings @((New-SettingItem -Name 'DarkMode' -Status 'Modified'))
        }

        $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive

        $plan.Actions[0].Category | Should -Be 'Setting'
        $plan.Summary.Install | Should -Be 2
        $plan.Summary.Apply | Should -Be 1
        $plan.Summary.Changing | Should -Be 3
        $plan.Summary.EstimatedMinutes | Should -BeGreaterThan 0
    }

    Context 'profile scope' {
        It 'passes the profile through to the State Engine and adopts its scope label' {
            Mock -ModuleName DeploymentPlanner Get-PhoenixState {
                New-State -Scope 'Profile: Gaming' -Applications @((New-AppItem -Name 'Discord' -Status 'Missing'))
            }

            $plan = New-PhoenixDeploymentPlan -RootPath $TestDrive -ProfileName 'Gaming'

            $plan.Scope | Should -Be 'Profile: Gaming'
            Should -Invoke -ModuleName DeploymentPlanner Get-PhoenixState -Times 1 -ParameterFilter { $ProfileName -eq 'Gaming' }
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
