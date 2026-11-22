BeforeAll {
    Import-Module "$PSScriptRoot/../modules/PlanContracts/PlanContracts.psd1" -Force
    function New-TestAction {
        [pscustomobject]@{
            ActionId = 'action-001'; Category = 'Application'; Name = 'TestApp'
            ManifestIdentity = 'applications/TestApp.json#sha256:abc123'; Action = 'Install'
            Parameters = @{ PackageId = 'Vendor.TestApp'; Backend = 'Winget' }
            Reason = 'Missing from desired state.'; Risk = 'Low'; Order = 0; Dependencies = @()
        }
    }
    function New-TestPlan {
        $args = @{
            Machine = @{ MachineId = 'machine-001'; ComputerName = 'PHOENIX-TEST' }
            Scope = 'Profile: Test'; PhoenixVersion = '0.9.0'; SourceRevision = 'abcdef123456'
            ConfigurationFingerprint = ('a' * 64); ManifestFingerprint = ('b' * 64); StateFingerprint = ('c' * 64)
            Actions = @((New-TestAction)); Summary = @{ Install = 1; Apply = 0; Skip = 0; Defer = 0; Risk = 'Low' }
            PlanId = '11111111-1111-4111-8111-111111111111'; CreatedAt = [datetimeoffset]::Parse('2026-11-22T10:00:00Z')
        }
        New-PhoenixDeploymentPlanContract @args
    }
    function New-TestApproval {
        param($Plan, [datetimeoffset]$At = [datetimeoffset]::Parse('2026-11-22T10:01:00Z'))
        [pscustomobject]@{
            SchemaVersion = '1.0'; ApprovalId = '22222222-2222-4222-8222-222222222222'
            PlanId = $Plan.PlanId; PlanDigest = $Plan.PlanDigest; Decision = 'Approved'
            Approver = @{ Name = 'PHOENIX-TEST\Operator'; Sid = 'S-1-5-21-1000' }
            ApprovedAt = $At.ToString('o'); ExpiresAt = $At.AddHours(4).ToString('o')
            MachineId = $Plan.Machine.MachineId; ComputerName = $Plan.Machine.ComputerName
            Scope = $Plan.Scope; ConfigurationFingerprint = $Plan.ConfigurationFingerprint
            ManifestFingerprint = $Plan.ManifestFingerprint; PhoenixVersion = $Plan.PhoenixVersion
            PlanSchemaVersion = $Plan.SchemaVersion
        }
    }
}

Describe 'Phoenix canonical JSON and plan digest' {
    It 'sorts object keys and preserves array order' {
        $a = ConvertTo-PhoenixCanonicalJson -InputObject ([ordered]@{ z = 1; a = 2; list = @(3, 1) })
        $b = ConvertTo-PhoenixCanonicalJson -InputObject ([ordered]@{ list = @(3, 1); a = 2; z = 1 })
        $a | Should -Be $b
        $a | Should -Be '{"a":2,"list":[3,1],"z":1}'
    }
    It 'normalises equivalent date-time offsets to UTC' {
        $a = ConvertTo-PhoenixCanonicalJson -InputObject @{ when = [datetimeoffset]::Parse('2026-11-22T10:00:00Z') }
        $b = ConvertTo-PhoenixCanonicalJson -InputObject @{ when = [datetimeoffset]::Parse('2026-11-22T11:00:00+01:00') }
        $a | Should -Be $b
    }
    It 'creates a valid plan and deterministic SHA-256 digest' {
        $plan = New-TestPlan
        $plan.SchemaVersion | Should -Be '1.0'
        $plan.PlanDigest | Should -Match '^[a-f0-9]{64}$'
        Assert-PhoenixDeploymentPlanContract -Plan $plan | Should -BeTrue
        (Get-PhoenixDeploymentPlanDigest -Plan $plan) | Should -Be $plan.PlanDigest
    }
    It 'produces the same digest when object property order changes' {
        $plan = New-TestPlan
        $reordered = [pscustomobject]@{
            PlanDigest = $plan.PlanDigest; DigestAlgorithm = $plan.DigestAlgorithm
            Summary = $plan.Summary; Actions = $plan.Actions; StateFingerprint = $plan.StateFingerprint
            ManifestFingerprint = $plan.ManifestFingerprint; ConfigurationFingerprint = $plan.ConfigurationFingerprint
            Scope = $plan.Scope; Machine = $plan.Machine; SourceRevision = $plan.SourceRevision
            PhoenixVersion = $plan.PhoenixVersion; CreatedAt = $plan.CreatedAt
            PlanId = $plan.PlanId; SchemaVersion = $plan.SchemaVersion
        }
        (Get-PhoenixDeploymentPlanDigest -Plan $reordered) | Should -Be $plan.PlanDigest
    }
    It 'detects a changed execution parameter' {
        $plan = New-TestPlan
        $plan.Actions[0].Parameters.PackageId = 'Attacker.OtherPackage'
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*PlanDigest*'
    }
    It 'detects changed machine context' {
        $plan = New-TestPlan
        $plan.Machine.MachineId = 'machine-002'
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*PlanDigest*'
    }
    It 'rejects unsupported schema, missing manifest identity and duplicate action IDs' {
        $plan = New-TestPlan
        $plan.SchemaVersion = '9.9'
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*Unsupported plan schema*'
        $plan = New-TestPlan
        $plan.Actions[0].ManifestIdentity = ''
        $plan.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $plan
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*manifest identity*'
        $action = New-TestAction
        $input = @{
            Machine = @{ MachineId = 'machine-001'; ComputerName = 'PHOENIX-TEST' }
            Scope = 'Test'; PhoenixVersion = '0.9.0'; SourceRevision = ''
            ConfigurationFingerprint = ('a' * 64); ManifestFingerprint = ('b' * 64); StateFingerprint = ('c' * 64)
            Actions = @($action, $action); Summary = @{ Risk = 'Low' }
        }
        { New-PhoenixDeploymentPlanContract @input } | Should -Throw '*Duplicate ActionId*'
    }
    It 'rejects unknown actions and dependency references' {
        $plan = New-TestPlan
        $plan.Actions[0].Action = 'RunArbitraryScript'
        $plan.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $plan
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*Unsupported action*'
        $plan = New-TestPlan
        $plan.Actions[0].Dependencies = @('missing-action')
        $plan.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $plan
        { Assert-PhoenixDeploymentPlanContract -Plan $plan } | Should -Throw '*unknown dependency*'
    }
    It 'rejects malformed SHA-256 fingerprints' {
        $input = @{
            Machine = @{ MachineId = 'machine'; ComputerName = 'PC' }; Scope = 'Test'
            PhoenixVersion = '0.9.0'; SourceRevision = ''; ConfigurationFingerprint = 'bad'
            ManifestFingerprint = ('b' * 64); StateFingerprint = ('c' * 64); Actions = @(); Summary = @{}
        }
        { New-PhoenixDeploymentPlanContract @input } | Should -Throw '*64-character hexadecimal*'
    }
}

Describe 'Phoenix approval record' {
    It 'accepts an approval bound to the exact plan and valid time window' {
        $plan = New-TestPlan
        $approval = New-TestApproval -Plan $plan
        $now = [datetimeoffset]::Parse('2026-11-22T10:02:00Z')
        Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval -Now $now | Should -BeTrue
        Test-PhoenixApprovalRecord -Plan $plan -Approval $approval -Now $now | Should -BeTrue
    }
    It 'rejects mismatched plan digest and plan ID' {
        $plan = New-TestPlan
        $approval = New-TestApproval -Plan $plan
        $approval.PlanDigest = '0' * 64
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval } | Should -Throw '*PlanDigest*'
        $approval = New-TestApproval -Plan $plan
        $approval.PlanId = '33333333-3333-4333-8333-333333333333'
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval } | Should -Throw '*PlanId*'
    }
    It 'rejects machine, scope and fingerprint mismatches' {
        $plan = New-TestPlan
        foreach ($field in @('MachineId', 'ComputerName', 'Scope', 'ConfigurationFingerprint', 'ManifestFingerprint', 'PhoenixVersion', 'PlanSchemaVersion')) {
            $approval = New-TestApproval -Plan $plan
            $approval.$field = 'mismatch'
            { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval } | Should -Throw "*$field*"
        }
    }
    It 'rejects expired and future-dated approvals' {
        $plan = New-TestPlan
        $approval = New-TestApproval -Plan $plan
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval -Now ([datetimeoffset]::Parse('2026-11-22T15:00:00Z')) } | Should -Throw '*expired*'
        $approval = New-TestApproval -Plan $plan -At ([datetimeoffset]::Parse('2026-11-23T00:00:00Z'))
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval -Now ([datetimeoffset]::Parse('2026-11-22T10:00:00Z')) } | Should -Throw '*future*'
    }
    It 'rejects denied decisions and missing Windows approver identity' {
        $plan = New-TestPlan
        $approval = New-TestApproval -Plan $plan
        $approval.Decision = 'Denied'
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval } | Should -Throw '*not Approved*'
        $approval = New-TestApproval -Plan $plan
        $approval.Approver.Sid = ''
        { Assert-PhoenixApprovalRecord -Plan $plan -Approval $approval } | Should -Throw '*Windows approver*'
    }
    It 'fails closed when the approval session is non-interactive' {
        $plan = New-TestPlan
        Mock -ModuleName PlanContracts Test-PhoenixInteractiveSession { $false }
        { New-PhoenixApprovalRecord -Plan $plan -ApprovalPath (Join-Path $TestDrive 'approval.json') } | Should -Throw '*interactive Windows ConsoleHost*'
        Test-Path (Join-Path $TestDrive 'approval.json') | Should -BeFalse
    }
    It 'requires exact uppercase APPROVE confirmation' {
        $plan = New-TestPlan
        Mock -ModuleName PlanContracts Test-PhoenixInteractiveSession { $true }
        Mock -ModuleName PlanContracts Read-Host { 'approve' }
        { New-PhoenixApprovalRecord -Plan $plan -ApprovalPath (Join-Path $TestDrive 'approval.json') } | Should -Throw '*Approval denied*'
        Test-Path (Join-Path $TestDrive 'approval.json') | Should -BeFalse
    }
    It 'writes a separate approval artefact after explicit confirmation' {
        $plan = New-TestPlan
        Mock -ModuleName PlanContracts Test-PhoenixInteractiveSession { $true }
        Mock -ModuleName PlanContracts Read-Host { 'APPROVE' }
        Mock -ModuleName PlanContracts Get-PhoenixCurrentApproverIdentity {
            [pscustomobject]@{ Name = 'PHOENIX-TEST\Operator'; Sid = 'S-1-5-21-1000' }
        }
        $path = Join-Path $TestDrive 'approvals/plan.approval.json'
        $approval = New-PhoenixApprovalRecord -Plan $plan -ApprovalPath $path
        Test-Path $path | Should -BeTrue
        (Get-Content $path -Raw | ConvertFrom-Json).PlanDigest | Should -Be $plan.PlanDigest
        $approval.Approver.Sid | Should -Be 'S-1-5-21-1000'
    }
}
