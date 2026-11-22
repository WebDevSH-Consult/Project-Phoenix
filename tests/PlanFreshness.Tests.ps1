BeforeAll {
    Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
    Import-Module "$PSScriptRoot/../modules/PlanFreshness/PlanFreshness.psd1" -Force
    Import-Module "$PSScriptRoot/../modules/PlanContracts/PlanContracts.psd1" -Force
    Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

    function Write-Fixture {
        param([string]$Root)
        $files = @{
            'VERSION'                                          = '0.9.0'
            'modules/Installer/Applications/git.json'          = '{ "Name": "Git", "Installer": "Winget", "Id": "Git.Git", "ConfigFlag": "applications.InstallGit", "Validate": [], "Dependencies": [], "RunOrder": 100 }'
            'modules/Installer/Applications/vscode.json'       = '{ "Name": "Visual Studio Code", "Installer": "Winget", "Id": "Microsoft.VisualStudioCode", "ConfigFlag": "applications.InstallVSCode", "Validate": [], "Dependencies": ["Git"], "RunOrder": 110 }'
            'modules/WindowsConfig/Settings/dark.json'         = '{ "Name": "Dark mode (apps)", "Type": "Registry", "ConfigFlag": "windows.DarkMode", "Path": "HKCU:\\Software\\Test", "ValueName": "AppsUseLightTheme", "DesiredValue": 0, "ValueKind": "DWord", "RequiresElevation": true }'
            'profiles/development.json'                        = '{ "Name": "Development", "Applications": ["Visual Studio Code"] }'
        }
        foreach ($relative in $files.Keys) {
            $path = Join-Path $Root $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path, $files[$relative])
        }
        Remove-Item -LiteralPath (Join-Path $Root 'modules/WindowsConfig/Settings/extra.json') -ErrorAction SilentlyContinue
    }

    function Get-FixtureManifest {
        param([string]$Root, [string]$RelativePath)
        Get-Content -LiteralPath (Join-Path $Root $RelativePath) -Raw | ConvertFrom-Json
    }

    # A minimal model of the live machine. The State Engine and Planner are
    # mocked from it, mirroring their real decision rules (ADR 0016/0018).
    function Reset-World {
        $script:World = @{
            Scope         = 'Configuration'
            Elevated      = $true
            PreflightSafe = $true
            Statuses      = [ordered]@{ 'Setting/Dark mode (apps)' = 'Modified'; 'Application/Git' = 'Present'; 'Application/Visual Studio Code' = 'Missing' }
            Hardware      = @{ MemoryGB = 32 }
            Reasons       = @{}
        }
        $script:Machine = [pscustomobject]@{ MachineId = '6f1d1b9e-0d4c-4b6a-9a51-3a1f6f0c0b11'; ComputerName = 'PHOENIX-TEST' }
        $script:Config = [pscustomobject]@{ version = '0.9.0'; Modules = [pscustomobject]@{ windows = [pscustomobject]@{ DarkMode = $true } } }
    }

    function Get-WorldState {
        $applications = @(); $settings = @()
        foreach ($key in $script:World.Statuses.Keys) {
            $category, $name = $key -split '/', 2
            $file = switch ($name) { 'Git' { 'modules/Installer/Applications/git.json' } 'Visual Studio Code' { 'modules/Installer/Applications/vscode.json' } default { 'modules/WindowsConfig/Settings/dark.json' } }
            $item = [pscustomobject]@{ Category = $category; Name = $name; Status = $script:World.Statuses[$key]; Manifest = (Get-FixtureManifest -Root $TestDrive -RelativePath $file) }
            if ($category -eq 'Application') { $applications += $item } else { $settings += $item }
        }
        [pscustomobject]@{ Timestamp = (Get-Date).ToString('o'); ComputerName = 'PHOENIX-TEST'; Scope = $script:World.Scope; Applications = $applications; Settings = $settings }
    }

    function Get-WorldPlannerPlan {
        $state = Get-WorldState
        $actions = @()
        foreach ($item in $state.Settings) {
            $actions += if ($item.Status -eq 'Applied') { [pscustomobject]@{ Category = 'Setting'; Name = $item.Name; Action = 'Skip'; Reason = 'Already in the desired state.'; Risk = 'Low'; EstimatedSeconds = 0 } }
            elseif (-not $script:World.Elevated) { [pscustomobject]@{ Category = 'Setting'; Name = $item.Name; Action = 'Defer'; Reason = 'Requires elevation - re-run elevated to apply.'; Risk = 'Medium'; EstimatedSeconds = 0 } }
            else { [pscustomobject]@{ Category = 'Setting'; Name = $item.Name; Action = 'Apply'; Reason = 'Not in the desired state.'; Risk = 'Medium'; EstimatedSeconds = 5 } }
        }
        foreach ($item in $state.Applications) {
            $actions += if ($item.Status -ne 'Missing') { [pscustomobject]@{ Category = 'Application'; Name = $item.Name; Action = 'Skip'; Reason = 'Already installed.'; Risk = 'Low'; EstimatedSeconds = 0 } }
            elseif (-not $script:World.PreflightSafe) { [pscustomobject]@{ Category = 'Application'; Name = $item.Name; Action = 'Defer'; Reason = 'System not in a safe state for installation (Pending reboot).'; Risk = 'Low'; EstimatedSeconds = 0 } }
            else { [pscustomobject]@{ Category = 'Application'; Name = $item.Name; Action = 'Install'; Reason = 'Not installed.'; Risk = 'Low'; EstimatedSeconds = 120 } }
        }
        foreach ($action in $actions) {
            $key = "$($action.Category)/$($action.Name)"
            if ($script:World.Reasons.ContainsKey($key)) { $action.Reason = $script:World.Reasons[$key] }
        }
        [pscustomobject]@{
            Timestamp     = (Get-Date).ToString('o')
            Machine       = [pscustomobject]@{ ComputerName = 'PHOENIX-TEST'; FormFactor = 'Desktop'; MemoryGB = $script:World.Hardware.MemoryGB }
            Scope         = $script:World.Scope
            Elevated      = $script:World.Elevated
            PreflightSafe = $script:World.PreflightSafe
            Actions       = $actions
            Summary       = [pscustomobject]@{ Install = @($actions | Where-Object Action -eq 'Install').Count; Risk = 'Medium' }
        }
    }

    function Use-WorldMocks {
        Mock -ModuleName PlanFreshness Get-PhoenixMachineIdentity { $script:Machine }
        Mock -ModuleName PlanFreshness Get-PhoenixSourceRevision { 'abc123' }
        Mock -ModuleName PlanFreshness Get-PhoenixConfiguration { $script:Config }
        Mock -ModuleName PlanFreshness Get-PhoenixState { Get-WorldState }
        Mock -ModuleName PlanFreshness New-PhoenixDeploymentPlan { Get-WorldPlannerPlan }
    }

    function New-ApprovedPlan {
        New-PhoenixContractPlan -RootPath $TestDrive -CreatedAt ([datetimeoffset]::Parse('2026-11-22T10:00:00Z')) -PlanId '11111111-1111-4111-8111-111111111111'
    }

    function Save-AndReload {
        param($Plan)
        $path = Join-Path $TestDrive 'plans/approved.plan.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, (ConvertTo-PhoenixCanonicalJson -InputObject $Plan))
        Read-PhoenixDeploymentPlanContract -Path $path
    }
}

Describe 'Machine identity' {
    It 'reads the Windows MachineGuid and computer name' -Skip:(-not $IsWindows) {
        $identity = Get-PhoenixMachineIdentity
        $identity.MachineId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        $identity.ComputerName | Should -Be ([Environment]::MachineName)
    }
    It 'fails closed when the MachineGuid cannot be read' -Skip:(-not $IsWindows) {
        Mock -ModuleName PlanFreshness Get-ItemPropertyValue { throw 'Access denied' }
        { Get-PhoenixMachineIdentity } | Should -Throw '*MachineGuid*'
    }
    It 'fails closed when the MachineGuid is not a GUID' -Skip:(-not $IsWindows) {
        Mock -ModuleName PlanFreshness Get-ItemPropertyValue { 'not-a-guid' }
        { Get-PhoenixMachineIdentity } | Should -Throw '*not a valid GUID*'
    }
}

Describe 'Plan fingerprints' {
    BeforeEach { Write-Fixture -Root $TestDrive; Reset-World }

    It 'gives the same configuration fingerprint regardless of key order, and a new one when a value changes' {
        Mock -ModuleName PlanFreshness Get-PhoenixConfiguration { [ordered]@{ a = 1; b = [ordered]@{ x = $true; y = 'z' } } }
        $first = Get-PhoenixConfigurationFingerprint -RootPath $TestDrive
        Mock -ModuleName PlanFreshness Get-PhoenixConfiguration { [ordered]@{ b = [ordered]@{ y = 'z'; x = $true }; a = 1 } }
        Get-PhoenixConfigurationFingerprint -RootPath $TestDrive | Should -Be $first
        Mock -ModuleName PlanFreshness Get-PhoenixConfiguration { [ordered]@{ a = 1; b = [ordered]@{ x = $false; y = 'z' } } }
        Get-PhoenixConfigurationFingerprint -RootPath $TestDrive | Should -Not -Be $first
    }

    It 'ignores formatting-only manifest edits but detects value changes and new manifests' {
        $first = Get-PhoenixManifestFingerprint -RootPath $TestDrive
        $first.Fingerprint | Should -Match '^[a-f0-9]{64}$'

        $gitPath = Join-Path $TestDrive 'modules/Installer/Applications/git.json'
        $reformatted = (Get-Content $gitPath -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($gitPath, $reformatted)
        (Get-PhoenixManifestFingerprint -RootPath $TestDrive).Fingerprint | Should -Be $first.Fingerprint

        [IO.File]::WriteAllText($gitPath, $reformatted.Replace('Git.Git', 'Attacker.Git'))
        $changed = Get-PhoenixManifestFingerprint -RootPath $TestDrive
        $changed.Fingerprint | Should -Not -Be $first.Fingerprint
        $changed.Identities['Application/Git'].Identity | Should -Not -Be $first.Identities['Application/Git'].Identity

        Write-Fixture -Root $TestDrive
        [IO.File]::WriteAllText((Join-Path $TestDrive 'modules/WindowsConfig/Settings/extra.json'), '{ "Name": "Unrelated" }')
        (Get-PhoenixManifestFingerprint -RootPath $TestDrive).Fingerprint | Should -Not -Be $first.Fingerprint
    }

    It 'returns per-item identities with path and hash' {
        $result = Get-PhoenixManifestFingerprint -RootPath $TestDrive
        $result.Identities['Application/Git'].Identity | Should -Match '^Application/Git#sha256:[a-f0-9]{64}$'
        $result.Identities['Application/Git'].RelativePath | Should -Be 'modules/Installer/Applications/git.json'
        $result.Identities['Setting/Dark mode (apps)'].RelativePath | Should -Be 'modules/WindowsConfig/Settings/dark.json'
        $result.Identities.Keys | Should -Not -Contain 'Profile/Development'
    }

    It 'rejects two manifests declaring the same name' {
        [IO.File]::WriteAllText((Join-Path $TestDrive 'modules/Installer/Applications/git2.json'), '{ "Name": "Git", "Installer": "Winget" }')
        try { { Get-PhoenixManifestFingerprint -RootPath $TestDrive } | Should -Throw '*Duplicate manifest identity*' }
        finally { Remove-Item (Join-Path $TestDrive 'modules/Installer/Applications/git2.json') }
    }

    It 'ignores timestamps and item order in the state fingerprint but not status, elevation or preflight' {
        $state = Get-WorldState
        $first = Get-PhoenixStateFingerprint -State $state -Elevated $true -PreflightSafe $true

        $state.Timestamp = '2030-01-01T00:00:00Z'
        $state.Applications = @($state.Applications[1], $state.Applications[0])
        Get-PhoenixStateFingerprint -State $state -Elevated $true -PreflightSafe $true | Should -Be $first

        Get-PhoenixStateFingerprint -State $state -Elevated $false -PreflightSafe $true | Should -Not -Be $first
        Get-PhoenixStateFingerprint -State $state -Elevated $true -PreflightSafe $false | Should -Not -Be $first
        $state.Applications[0].Status = 'Outdated'
        Get-PhoenixStateFingerprint -State $state -Elevated $true -PreflightSafe $true | Should -Not -Be $first
    }
}

Describe 'New-PhoenixContractPlan' {
    BeforeEach { Write-Fixture -Root $TestDrive; Reset-World; Use-WorldMocks }

    It 'builds a valid contract plan from the planner with full provenance' {
        $plan = New-ApprovedPlan
        Assert-PhoenixDeploymentPlanContract -Plan $plan | Should -BeTrue
        $plan.Machine.MachineId | Should -Be $script:Machine.MachineId
        $plan.PhoenixVersion | Should -Be '0.9.0'
        $plan.SourceRevision | Should -Be 'abc123'
        $plan.Scope | Should -Be 'Configuration'
        $plan.Summary.Elevated | Should -BeTrue
        $plan.Summary.PreflightSafe | Should -BeTrue
    }

    It 'gives stable action IDs, manifest identities, parameters and order' {
        $plan = New-ApprovedPlan
        @($plan.Actions.ActionId) | Should -Be @('setting:dark-mode-apps', 'application:git', 'application:visual-studio-code')
        @($plan.Actions.Order) | Should -Be @(0, 1, 2)
        @($plan.Actions.Action) | Should -Be @('Apply', 'Skip', 'Install')
        $plan.Actions[2].ManifestIdentity | Should -Match '^Application/Visual Studio Code#sha256:[a-f0-9]{64}$'
        $plan.Actions[2].Parameters.ManifestPath | Should -Be 'modules/Installer/Applications/vscode.json'
    }

    It 'maps manifest dependencies to action IDs' {
        $plan = New-ApprovedPlan
        @($plan.Actions[2].Dependencies) | Should -Be @('application:git')
        @($plan.Actions[1].Dependencies).Count | Should -Be 0
    }

    It 'carries planner Skip and Defer decisions unchanged' {
        $script:World.Elevated = $false
        $script:World.PreflightSafe = $false
        $plan = New-ApprovedPlan
        @($plan.Actions.Action) | Should -Be @('Defer', 'Skip', 'Defer')
    }

    It 'refuses a dependency that is outside the plan scope' {
        $script:World.Statuses.Remove('Application/Git')
        { New-ApprovedPlan } | Should -Throw "*depends on 'Git'*"
    }

    It 'refuses when the State Engine and planner disagree on scope' {
        Mock -ModuleName PlanFreshness Get-PhoenixState { $s = Get-WorldState; $s.Scope = 'Profile: Development'; $s }
        { New-ApprovedPlan } | Should -Throw '*does not match planner scope*'
    }
}

Describe 'Plan freshness gate' {
    BeforeEach { Write-Fixture -Root $TestDrive; Reset-World; Use-WorldMocks }

    It 'accepts an unchanged plan after it is saved and reloaded' {
        $approved = Save-AndReload -Plan (New-ApprovedPlan)
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeTrue
        $result.FailedChecks | Should -BeNullOrEmpty
        @($result.Checks.Name) | Should -Be @('PlanContract', 'Scope', 'MachineIdentity', 'PhoenixVersion', 'ConfigurationFingerprint', 'ManifestFingerprint', 'StateFingerprint', 'ActionSet')
        $result.PlanDigest | Should -Be $approved.PlanDigest
    }

    It 'does not treat timestamps, hardware detail, reasons or source revision as staleness' {
        $approved = Save-AndReload -Plan (New-ApprovedPlan)
        $script:World.Hardware.MemoryGB = 64
        $script:World.Reasons['Application/Visual Studio Code'] = 'Reworded explanation.'
        Mock -ModuleName PlanFreshness Get-PhoenixSourceRevision { 'def456' }
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeTrue
        $result.SourceRevisionNote | Should -BeLike 'Informational*def456*'
    }

    It 'rejects a plan approved on a different machine' {
        $approved = New-ApprovedPlan
        $script:Machine = [pscustomobject]@{ MachineId = '00000000-0000-4000-8000-000000000001'; ComputerName = 'PHOENIX-TEST' }
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeFalse
        $result.FailedChecks | Should -Contain 'MachineIdentity'
    }

    It 'rejects a renamed computer' {
        $approved = New-ApprovedPlan
        $script:Machine = [pscustomobject]@{ MachineId = $script:Machine.MachineId; ComputerName = 'RENAMED-PC' }
        (Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).FailedChecks | Should -Contain 'MachineIdentity'
    }

    It 'rejects after a Phoenix version change' {
        $approved = New-ApprovedPlan
        [IO.File]::WriteAllText((Join-Path $TestDrive 'VERSION'), '0.9.1')
        (Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).FailedChecks | Should -Contain 'PhoenixVersion'
    }

    It 'rejects after a configuration change' {
        $approved = New-ApprovedPlan
        $script:Config.Modules.windows.DarkMode = $false
        (Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).FailedChecks | Should -Contain 'ConfigurationFingerprint'
    }

    It 'rejects after a manifest change, including the affected action identity' {
        $approved = New-ApprovedPlan
        $path = Join-Path $TestDrive 'modules/Installer/Applications/vscode.json'
        [IO.File]::WriteAllText($path, (Get-Content $path -Raw).Replace('Microsoft.VisualStudioCode', 'Other.Package'))
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.FailedChecks | Should -Contain 'ManifestFingerprint'
        $result.FailedChecks | Should -Contain 'ActionSet'
        ($result.Checks | Where-Object Name -eq 'ActionSet').Detail | Should -BeLike "*application:visual-studio-code*ManifestIdentity*"
    }

    It 'rejects when state changes make an approved action unnecessary' {
        $approved = New-ApprovedPlan
        $script:World.Statuses['Application/Visual Studio Code'] = 'Present'
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.FailedChecks | Should -Contain 'StateFingerprint'
        $result.FailedChecks | Should -Contain 'ActionSet'
        ($result.Checks | Where-Object Name -eq 'ActionSet').Detail | Should -BeLike '*approved Install, now Skip*'
    }

    It 'rejects when elevation is lost after approval' {
        $approved = New-ApprovedPlan
        $script:World.Elevated = $false
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.FailedChecks | Should -Contain 'StateFingerprint'
        ($result.Checks | Where-Object Name -eq 'ActionSet').Detail | Should -BeLike '*setting:dark-mode-apps*approved Apply, now Defer*'
    }

    It 'rejects when installer preflight becomes unsafe after approval' {
        $approved = New-ApprovedPlan
        $script:World.PreflightSafe = $false
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeFalse
        ($result.Checks | Where-Object Name -eq 'ActionSet').Detail | Should -BeLike '*application:visual-studio-code*approved Install, now Defer*'
    }

    It 'rejects when a new item comes into scope' {
        $approved = New-ApprovedPlan
        [IO.File]::WriteAllText((Join-Path $TestDrive 'modules/Installer/Applications/sevenzip.json'), '{ "Name": "7-Zip", "Installer": "Winget", "Id": "7zip.7zip", "ConfigFlag": "applications.Install7Zip", "Validate": [] }')
        $script:World.Statuses['Application/7-Zip'] = 'Present'
        Mock -ModuleName PlanFreshness Get-PhoenixState {
            $s = Get-WorldState
            $s.Applications | Where-Object Name -eq '7-Zip' | ForEach-Object { $_.Manifest = [pscustomobject]@{ Name = '7-Zip'; Dependencies = @() } }
            $s
        }
        try {
            ($result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).Fresh | Should -BeFalse
            ($result.Checks | Where-Object Name -eq 'ActionSet').Detail | Should -BeLike "*'application:7-zip' is newly planned*"
        }
        finally { Remove-Item (Join-Path $TestDrive 'modules/Installer/Applications/sevenzip.json') }
    }

    It 'rejects a tampered plan without rebuilding anything' {
        $approved = Save-AndReload -Plan (New-ApprovedPlan)
        $approved.Actions[2].Action = 'Skip'
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeFalse
        $result.FailedChecks | Should -Be @('PlanContract')
        # One call built the approved plan above; the freshness check made none.
        Should -Invoke -ModuleName PlanFreshness New-PhoenixDeploymentPlan -Times 1 -Exactly
    }

    It 'rejects an unrecognised scope label' {
        $approved = New-ApprovedPlan
        $approved.Scope = 'Everything'
        $approved.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $approved
        (Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).FailedChecks | Should -Be @('Scope')
    }

    It 'rebuilds a profile-scoped plan with the same profile' {
        $script:World.Scope = 'Profile: Development'
        $approved = New-ApprovedPlan
        (Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).Fresh | Should -BeTrue
        Should -Invoke -ModuleName PlanFreshness New-PhoenixDeploymentPlan -ParameterFilter { $ProfileName -eq 'Development' }
    }

    It 'treats unknown freshness as stale' {
        $approved = New-ApprovedPlan
        Mock -ModuleName PlanFreshness Get-PhoenixState { throw 'WinGet unavailable' }
        $result = Test-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive
        $result.Fresh | Should -BeFalse
        $result.FailedChecks | Should -Be @('Evaluation')
        ($result.Checks | Where-Object Name -eq 'Evaluation').Detail | Should -BeLike '*WinGet unavailable*'
    }

    It 'Assert-PhoenixPlanFreshness returns the result when fresh and throws with reasons when stale' {
        $approved = New-ApprovedPlan
        (Assert-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive).Fresh | Should -BeTrue
        $script:World.PreflightSafe = $false
        { Assert-PhoenixPlanFreshness -Plan $approved -RootPath $TestDrive } | Should -Throw '*stale*ActionSet*'
    }
}
