# Project Phoenix Plan Contracts (PHX-005A).
# Contract validation only. This module never executes deployments.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:PlanSchemaVersion = '1.0'
$script:ApprovalSchemaVersion = '1.0'
$script:DigestAlgorithm = 'SHA256'
$script:FingerprintPattern = '^[a-fA-F0-9]{64}$'

function ConvertTo-PhoenixCanonicalNode {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or
        $Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) { return $Value }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [guid]) { return $Value.ToString('D') }
    if ($Value -is [enum]) { return $Value.ToString() }

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        $keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $sourceKey = @($Value.Keys | Where-Object { [string]$_ -ceq $key } | Select-Object -First 1)[0]
            $ordered[$key] = ConvertTo-PhoenixCanonicalNode -Value $Value[$sourceKey]
        }
        return ,$ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $items.Add((ConvertTo-PhoenixCanonicalNode -Value $item)) }
        return ,$items.ToArray()
    }
    if ($Value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        $properties = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property') | Sort-Object Name -CaseSensitive)
        foreach ($property in $properties) { $ordered[$property.Name] = ConvertTo-PhoenixCanonicalNode -Value $property.Value }
        return ,$ordered
    }
    throw "Unsupported canonical JSON value type '$($Value.GetType().FullName)'. Use JSON-compatible values only."
}

function ConvertTo-PhoenixCanonicalJson {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)
    $canonical = ConvertTo-PhoenixCanonicalNode -Value $InputObject
    return ConvertTo-Json -InputObject $canonical -Depth 100 -Compress
}

function Get-PhoenixDeploymentPlanDigest {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Plan)
    $copy = [ordered]@{}
    foreach ($property in $Plan.PSObject.Properties) {
        if ($property.Name -cne 'PlanDigest') { $copy[$property.Name] = $property.Value }
    }
    $json = ConvertTo-PhoenixCanonicalJson -InputObject $copy
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($sha).ToLowerInvariant()
}

function Assert-PhoenixFingerprint {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch $script:FingerprintPattern) {
        throw "$Name must be a 64-character hexadecimal SHA-256 fingerprint."
    }
}

function Assert-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Plan)
    $required = @('SchemaVersion', 'PlanId', 'CreatedAt', 'PhoenixVersion', 'SourceRevision',
        'Machine', 'Scope', 'ConfigurationFingerprint', 'ManifestFingerprint',
        'StateFingerprint', 'Actions', 'Summary', 'DigestAlgorithm', 'PlanDigest')
    foreach ($name in $required) {
        if ($Plan.PSObject.Properties.Name -cnotcontains $name) { throw "Plan is missing required field '$name'." }
    }
    if ($Plan.SchemaVersion -cne $script:PlanSchemaVersion) { throw "Unsupported plan schema version '$($Plan.SchemaVersion)'." }
    if ($Plan.DigestAlgorithm -cne $script:DigestAlgorithm) { throw "Unsupported plan digest algorithm '$($Plan.DigestAlgorithm)'." }
    $planGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Plan.PlanId, [ref]$planGuid) -or $planGuid -eq [guid]::Empty) { throw 'PlanId must be a non-empty GUID.' }
    $created = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Plan.CreatedAt, [ref]$created) -or $created.Offset -ne [timespan]::Zero) {
        throw 'CreatedAt must be a valid UTC ISO 8601 timestamp.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.PhoenixVersion)) { throw 'PhoenixVersion is required.' }
    if ($null -eq $Plan.SourceRevision) { throw 'SourceRevision must be present. Use an empty string when unavailable.' }
    if ($null -eq $Plan.Machine -or [string]::IsNullOrWhiteSpace([string]$Plan.Machine.MachineId) -or
        [string]::IsNullOrWhiteSpace([string]$Plan.Machine.ComputerName)) { throw 'Machine must contain non-empty MachineId and ComputerName values.' }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.Scope)) { throw 'Scope is required.' }
    Assert-PhoenixFingerprint -Name 'ConfigurationFingerprint' -Value ([string]$Plan.ConfigurationFingerprint)
    Assert-PhoenixFingerprint -Name 'ManifestFingerprint' -Value ([string]$Plan.ManifestFingerprint)
    Assert-PhoenixFingerprint -Name 'StateFingerprint' -Value ([string]$Plan.StateFingerprint)
    if ($Plan.Actions -isnot [System.Collections.IEnumerable] -or $Plan.Actions -is [string]) { throw 'Actions must be an array.' }
    if ($null -eq $Plan.Summary) { throw 'Summary is required.' }

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($action in @($Plan.Actions)) {
        if ($null -eq $action) { throw 'Actions cannot contain null entries.' }
        foreach ($field in @('ActionId', 'Category', 'Name', 'ManifestIdentity', 'Action', 'Parameters', 'Reason', 'Risk', 'Order', 'Dependencies')) {
            if ($action.PSObject.Properties.Name -cnotcontains $field) { throw "Action is missing required field '$field'." }
        }
        if ([string]$action.ActionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { throw 'ActionId must be a stable 1–128 character identifier.' }
        if ($action.Category -notin @('Application', 'Setting')) { throw "Unsupported action category '$($action.Category)'." }
        if ($action.Action -notin @('Install', 'Apply', 'Skip', 'Defer')) { throw "Unsupported action '$($action.Action)'." }
        if ($action.Action -eq 'Install' -and $action.Category -ne 'Application') { throw 'Install is only valid for Application actions.' }
        if ($action.Action -eq 'Apply' -and $action.Category -ne 'Setting') { throw 'Apply is only valid for Setting actions.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.Name)) { throw 'Action Name cannot be empty.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.ManifestIdentity)) { throw "Action '$($action.ActionId)' is missing its manifest identity." }
        if ($action.Parameters -isnot [System.Collections.IDictionary] -and $action.Parameters -isnot [pscustomobject]) { throw "Action '$($action.ActionId)' Parameters must be an object." }
        if ([string]::IsNullOrWhiteSpace([string]$action.Reason)) { throw "Action '$($action.ActionId)' Reason cannot be empty." }
        if ($action.Risk -notin @('Low', 'Medium', 'High', 'Critical')) { throw "Action '$($action.ActionId)' has an unsupported Risk value." }
        if (($action.Order -isnot [int16]) -and ($action.Order -isnot [int32]) -and ($action.Order -isnot [int64]) -and
            ($action.Order -isnot [uint16]) -and ($action.Order -isnot [uint32]) -and ($action.Order -isnot [uint64])) {
            throw "Action '$($action.ActionId)' Order must be a non-negative integer."
        }
        if ([decimal]$action.Order -lt 0) { throw "Action '$($action.ActionId)' Order must be a non-negative integer." }
        if ($action.Dependencies -isnot [System.Collections.IEnumerable] -or $action.Dependencies -is [string]) { throw "Action '$($action.ActionId)' Dependencies must be an array." }
    }
    $actionById = @{}
    foreach ($action in @($Plan.Actions)) { $actionById[[string]$action.ActionId] = $action }
    foreach ($action in @($Plan.Actions)) {
        foreach ($dependency in @($action.Dependencies)) {
            if ([string]$dependency -eq [string]$action.ActionId) { throw "Action '$($action.ActionId)' cannot depend on itself." }
            if (-not $ids.Contains([string]$dependency)) { throw "Action '$($action.ActionId)' references unknown dependency '$dependency'." }
        }
    }

    # Kahn's topological check rejects dependency cycles without recursion.
    $inDegree = @{}
    $dependents = @{}
    foreach ($action in @($Plan.Actions)) {
        $actionId = [string]$action.ActionId
        $inDegree[$actionId] = @($action.Dependencies).Count
        $dependents[$actionId] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($action in @($Plan.Actions)) {
        $actionId = [string]$action.ActionId
        foreach ($dependency in @($action.Dependencies)) {
            $dependents[[string]$dependency].Add($actionId)
        }
    }
    $ready = [System.Collections.Generic.Queue[string]]::new()
    foreach ($actionId in $inDegree.Keys) {
        if ($inDegree[$actionId] -eq 0) { $ready.Enqueue([string]$actionId) }
    }
    $visitedCount = 0
    while ($ready.Count -gt 0) {
        $currentId = $ready.Dequeue()
        $visitedCount++
        foreach ($dependentId in $dependents[$currentId]) {
            $inDegree[$dependentId]--
            if ($inDegree[$dependentId] -eq 0) { $ready.Enqueue($dependentId) }
        }
    }
    if ($visitedCount -ne $inDegree.Count) { throw 'Dependency cycle detected in the plan action graph.' }

    $actualDigest = Get-PhoenixDeploymentPlanDigest -Plan $Plan
    if ([string]$Plan.PlanDigest -cne $actualDigest) { throw 'PlanDigest does not match the canonical plan content.' }
    return $true
}

function Test-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][psobject]$Plan)
    try { return [bool](Assert-PhoenixDeploymentPlanContract -Plan $Plan) }
    catch { return $false }
}

function New-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Machine,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$PhoenixVersion,
        [Parameter(Mandatory)][AllowEmptyString()][string]$SourceRevision,
        [Parameter(Mandatory)][string]$ConfigurationFingerprint,
        [Parameter(Mandatory)][string]$ManifestFingerprint,
        [Parameter(Mandatory)][string]$StateFingerprint,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions,
        [Parameter(Mandatory)][psobject]$Summary,
        [string]$PlanId = ([guid]::NewGuid().ToString('D')),
        [datetimeoffset]$CreatedAt = [datetimeoffset]::UtcNow
    )
    $plan = [ordered]@{
        SchemaVersion = $script:PlanSchemaVersion
        PlanId = $PlanId
        CreatedAt = $CreatedAt.ToUniversalTime().ToString('o')
        PhoenixVersion = $PhoenixVersion
        SourceRevision = $SourceRevision
        Machine = $Machine
        Scope = $Scope
        ConfigurationFingerprint = $ConfigurationFingerprint.ToLowerInvariant()
        ManifestFingerprint = $ManifestFingerprint.ToLowerInvariant()
        StateFingerprint = $StateFingerprint.ToLowerInvariant()
        Actions = @($Actions)
        Summary = $Summary
        DigestAlgorithm = $script:DigestAlgorithm
        PlanDigest = ''
    }
    $result = [pscustomobject]$plan
    $result.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $result
    Assert-PhoenixDeploymentPlanContract -Plan $result | Out-Null
    return $result
}

function Test-PhoenixInteractiveSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost')
}

function Read-PhoenixApprovalConfirmation {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return Read-Host 'Type APPROVE to create the approval record'
}

function Get-PhoenixCurrentApproverIdentity {
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { throw 'Human plan approval is supported only from a Windows security context.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.Name) -or $null -eq $identity.User) {
        throw 'Could not resolve the current Windows approver identity.'
    }
    return [pscustomobject]@{ Name = $identity.Name; Sid = $identity.User.Value }
}

function New-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][string]$ApprovalPath,
        [ValidateRange(1, 24)][int]$ValidityHours = 4
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    if ([IO.Path]::GetFileName($ApprovalPath) -notmatch '\.approval\.json$') {
        throw 'ApprovalPath must be a separate file ending in .approval.json.'
    }
    $fullApprovalPath = [IO.Path]::GetFullPath($ApprovalPath)
    if (Test-Path -LiteralPath $fullApprovalPath) {
        throw 'Refusing to overwrite an existing approval record. Choose a new approval path.'
    }
    if (-not (Test-PhoenixInteractiveSession)) {
        throw 'Approval denied: an interactive Windows ConsoleHost session is required.'
    }

    Write-Host ''
    Write-Host 'PHOENIX DEPLOYMENT PLAN APPROVAL' -ForegroundColor Cyan
    Write-Host "Plan ID: $($Plan.PlanId)"
    Write-Host "Machine: $($Plan.Machine.ComputerName) [$($Plan.Machine.MachineId)]"
    Write-Host "Scope: $($Plan.Scope)"
    Write-Host "Risk: $($Plan.Summary.Risk)"
    Write-Host "Actions: $(@($Plan.Actions).Count)"
    Write-Host 'Full action contract (including parameters, dependencies and manifest identities):'
    Write-Host (ConvertTo-PhoenixCanonicalJson -InputObject @($Plan.Actions))
    Write-Host "SHA-256: $($Plan.PlanDigest)"
    Write-Host 'Approval applies only to this exact plan and context.'
    $response = Read-PhoenixApprovalConfirmation
    if ($response -cne 'APPROVE') { throw 'Approval denied. No approval record was created.' }

    $approver = Get-PhoenixCurrentApproverIdentity
    $approvedAt = [datetimeoffset]::UtcNow
    $approval = [pscustomobject][ordered]@{
        SchemaVersion = $script:ApprovalSchemaVersion
        ApprovalId = [guid]::NewGuid().ToString('D')
        PlanId = [string]$Plan.PlanId
        PlanDigest = [string]$Plan.PlanDigest
        Decision = 'Approved'
        Approver = $approver
        ApprovedAt = $approvedAt.ToString('o')
        ExpiresAt = $approvedAt.AddHours($ValidityHours).ToString('o')
        MachineId = [string]$Plan.Machine.MachineId
        ComputerName = [string]$Plan.Machine.ComputerName
        Scope = [string]$Plan.Scope
        ConfigurationFingerprint = [string]$Plan.ConfigurationFingerprint
        ManifestFingerprint = [string]$Plan.ManifestFingerprint
        PhoenixVersion = [string]$Plan.PhoenixVersion
        PlanSchemaVersion = [string]$Plan.SchemaVersion
    }
    Assert-PhoenixApprovalRecord -Plan $Plan -Approval $approval | Out-Null

    $parent = Split-Path -Parent $fullApprovalPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = ConvertTo-PhoenixCanonicalJson -InputObject $approval
    [IO.File]::WriteAllText($fullApprovalPath, $json, [Text.UTF8Encoding]::new($false))
    return $approval
}

function Assert-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    $required = @('SchemaVersion', 'ApprovalId', 'PlanId', 'PlanDigest', 'Decision', 'Approver',
        'ApprovedAt', 'ExpiresAt', 'MachineId', 'ComputerName', 'Scope',
        'ConfigurationFingerprint', 'ManifestFingerprint', 'PhoenixVersion', 'PlanSchemaVersion')
    foreach ($name in $required) {
        if ($Approval.PSObject.Properties.Name -cnotcontains $name) { throw "Approval is missing required field '$name'." }
    }
    if ($Approval.SchemaVersion -cne $script:ApprovalSchemaVersion) { throw "Unsupported approval schema version '$($Approval.SchemaVersion)'." }
    if ($Approval.Decision -cne 'Approved') { throw 'Approval decision is not Approved.' }
    $approvalGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Approval.ApprovalId, [ref]$approvalGuid) -or $approvalGuid -eq [guid]::Empty) { throw 'ApprovalId must be a non-empty GUID.' }
    if ([string]$Approval.PlanId -cne [string]$Plan.PlanId) { throw 'Approval PlanId does not match the plan.' }
    if ([string]$Approval.PlanDigest -cne [string]$Plan.PlanDigest) { throw 'Approval PlanDigest does not match the plan.' }
    if ([string]::IsNullOrWhiteSpace([string]$Approval.Approver.Name) -or [string]::IsNullOrWhiteSpace([string]$Approval.Approver.Sid)) {
        throw 'Approval must identify the Windows approver by name and SID.'
    }
    $pairs = @(
        @{ Field = 'MachineId'; Expected = [string]$Plan.Machine.MachineId },
        @{ Field = 'ComputerName'; Expected = [string]$Plan.Machine.ComputerName },
        @{ Field = 'Scope'; Expected = [string]$Plan.Scope },
        @{ Field = 'ConfigurationFingerprint'; Expected = [string]$Plan.ConfigurationFingerprint },
        @{ Field = 'ManifestFingerprint'; Expected = [string]$Plan.ManifestFingerprint },
        @{ Field = 'PhoenixVersion'; Expected = [string]$Plan.PhoenixVersion },
        @{ Field = 'PlanSchemaVersion'; Expected = [string]$Plan.SchemaVersion }
    )
    foreach ($pair in $pairs) {
        if ([string]$Approval.($pair.Field) -cne $pair.Expected) { throw "Approval $($pair.Field) does not match the plan." }
    }
    $approvedAt = [datetimeoffset]::MinValue
    $expiresAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Approval.ApprovedAt, [ref]$approvedAt)) { throw 'ApprovedAt is invalid.' }
    if (-not [datetimeoffset]::TryParse([string]$Approval.ExpiresAt, [ref]$expiresAt)) { throw 'ExpiresAt is invalid.' }
    if ($approvedAt -gt $Now.AddMinutes(5)) { throw 'Approval timestamp is in the future.' }
    if ($expiresAt -le $approvedAt) { throw 'Approval expiry must be later than the approval timestamp.' }
    if ($Now -ge $expiresAt) { throw 'Approval has expired.' }
    if ($expiresAt -gt $approvedAt.AddHours(24)) { throw 'Approval validity cannot exceed 24 hours.' }
    return $true
}

function Test-PhoenixApprovalRecord {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    try { return [bool](Assert-PhoenixApprovalRecord -Plan $Plan -Approval $Approval -Now $Now) }
    catch { return $false }
}

Export-ModuleMember -Function ConvertTo-PhoenixCanonicalJson, Get-PhoenixDeploymentPlanDigest,
    New-PhoenixDeploymentPlanContract, Assert-PhoenixDeploymentPlanContract,
    Test-PhoenixDeploymentPlanContract, New-PhoenixApprovalRecord,
    Assert-PhoenixApprovalRecord, Test-PhoenixApprovalRecord
) { throw 'ActionId must be a stable 1–128 character identifier.' }
        if (-not $ids.Add([string]$action.ActionId)) { throw "Duplicate ActionId '$($action.ActionId)'." }
        if ($action.Category -notin @('Application', 'Setting')) { throw "Unsupported action category '$($action.Category)'." }
        if ($action.Action -notin @('Install', 'Apply', 'Skip', 'Defer')) { throw "Unsupported action '$($action.Action)'." }
        if ($action.Action -eq 'Install' -and $action.Category -ne 'Application') { throw 'Install is only valid for Application actions.' }
        if ($action.Action -eq 'Apply' -and $action.Category -ne 'Setting') { throw 'Apply is only valid for Setting actions.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.Name)) { throw 'Action Name cannot be empty.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.ManifestIdentity)) { throw "Action '$($action.ActionId)' is missing its manifest identity." }
        if ($action.Parameters -isnot [System.Collections.IDictionary] -and $action.Parameters -isnot [pscustomobject]) { throw "Action '$($action.ActionId)' Parameters must be an object." }
        if ([string]::IsNullOrWhiteSpace([string]$action.Reason)) { throw "Action '$($action.ActionId)' Reason cannot be empty." }
        if ($action.Risk -notin @('Low', 'Medium', 'High', 'Critical')) { throw "Action '$($action.ActionId)' has an unsupported Risk value." }
        if ($action.Order -isnot [ValueType] -or $action.Order -is [bool] -or [int]$action.Order -lt 0) { throw "Action '$($action.ActionId)' Order must be a non-negative integer." }
        if ($action.Dependencies -isnot [System.Collections.IEnumerable] -or $action.Dependencies -is [string]) { throw "Action '$($action.ActionId)' Dependencies must be an array." }
    }
    foreach ($action in @($Plan.Actions)) {
        foreach ($dependency in @($action.Dependencies)) {
            if ([string]$dependency -eq [string]$action.ActionId) { throw "Action '$($action.ActionId)' cannot depend on itself." }
            if (-not $ids.Contains([string]$dependency)) { throw "Action '$($action.ActionId)' references unknown dependency '$dependency'." }
        }
    }
    $actualDigest = Get-PhoenixDeploymentPlanDigest -Plan $Plan
    if ([string]$Plan.PlanDigest -cne $actualDigest) { throw 'PlanDigest does not match the canonical plan content.' }
    return $true
}

function Test-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][psobject]$Plan)
    try { return [bool](Assert-PhoenixDeploymentPlanContract -Plan $Plan) }
    catch { return $false }
}

function New-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Machine,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$PhoenixVersion,
        [Parameter(Mandatory)][AllowEmptyString()][string]$SourceRevision,
        [Parameter(Mandatory)][string]$ConfigurationFingerprint,
        [Parameter(Mandatory)][string]$ManifestFingerprint,
        [Parameter(Mandatory)][string]$StateFingerprint,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions,
        [Parameter(Mandatory)][psobject]$Summary,
        [string]$PlanId = ([guid]::NewGuid().ToString('D')),
        [datetimeoffset]$CreatedAt = [datetimeoffset]::UtcNow
    )
    $plan = [ordered]@{
        SchemaVersion = $script:PlanSchemaVersion
        PlanId = $PlanId
        CreatedAt = $CreatedAt.ToUniversalTime().ToString('o')
        PhoenixVersion = $PhoenixVersion
        SourceRevision = $SourceRevision
        Machine = $Machine
        Scope = $Scope
        ConfigurationFingerprint = $ConfigurationFingerprint.ToLowerInvariant()
        ManifestFingerprint = $ManifestFingerprint.ToLowerInvariant()
        StateFingerprint = $StateFingerprint.ToLowerInvariant()
        Actions = @($Actions)
        Summary = $Summary
        DigestAlgorithm = $script:DigestAlgorithm
        PlanDigest = ''
    }
    $result = [pscustomobject]$plan
    $result.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $result
    Assert-PhoenixDeploymentPlanContract -Plan $result | Out-Null
    return $result
}

function Test-PhoenixInteractiveSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost')
}

function Get-PhoenixCurrentApproverIdentity {
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { throw 'Human plan approval is supported only from a Windows security context.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.Name) -or $null -eq $identity.User) {
        throw 'Could not resolve the current Windows approver identity.'
    }
    return [pscustomobject]@{ Name = $identity.Name; Sid = $identity.User.Value }
}

function New-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][string]$ApprovalPath,
        [ValidateRange(1, 24)][int]$ValidityHours = 4
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    if (-not (Test-PhoenixInteractiveSession)) { throw 'Approval denied: an interactive Windows ConsoleHost session is required.' }
    Write-Host ''
    Write-Host 'PHOENIX DEPLOYMENT PLAN APPROVAL' -ForegroundColor Cyan
    Write-Host "Plan ID: $($Plan.PlanId)"
    Write-Host "Machine: $($Plan.Machine.ComputerName) [$($Plan.Machine.MachineId)]"
    Write-Host "Scope: $($Plan.Scope)"
    Write-Host "Risk: $($Plan.Summary.Risk)"
    Write-Host "Actions: $(@($Plan.Actions).Count)"
    Write-Host "SHA-256: $($Plan.PlanDigest)"
    Write-Host 'Approval applies only to this exact plan and context.'
    $response = Read-Host 'Type APPROVE to create the approval record'
    if ($response -cne 'APPROVE') { throw 'Approval denied. No approval record was created.' }
    $approver = Get-PhoenixCurrentApproverIdentity
    $approvedAt = [datetimeoffset]::UtcNow
    $approval = [pscustomobject][ordered]@{
        SchemaVersion = $script:ApprovalSchemaVersion
        ApprovalId = [guid]::NewGuid().ToString('D')
        PlanId = [string]$Plan.PlanId
        PlanDigest = [string]$Plan.PlanDigest
        Decision = 'Approved'
        Approver = $approver
        ApprovedAt = $approvedAt.ToString('o')
        ExpiresAt = $approvedAt.AddHours($ValidityHours).ToString('o')
        MachineId = [string]$Plan.Machine.MachineId
        ComputerName = [string]$Plan.Machine.ComputerName
        Scope = [string]$Plan.Scope
        ConfigurationFingerprint = [string]$Plan.ConfigurationFingerprint
        ManifestFingerprint = [string]$Plan.ManifestFingerprint
        PhoenixVersion = [string]$Plan.PhoenixVersion
        PlanSchemaVersion = [string]$Plan.SchemaVersion
    }
    Assert-PhoenixApprovalRecord -Plan $Plan -Approval $approval | Out-Null
    $parent = Split-Path -Parent $ApprovalPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ConvertTo-PhoenixCanonicalJson -InputObject $approval
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ApprovalPath), $json, [Text.UTF8Encoding]::new($false))
    return $approval
}

function Assert-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    $required = @('SchemaVersion', 'ApprovalId', 'PlanId', 'PlanDigest', 'Decision', 'Approver',
        'ApprovedAt', 'ExpiresAt', 'MachineId', 'ComputerName', 'Scope',
        'ConfigurationFingerprint', 'ManifestFingerprint', 'PhoenixVersion', 'PlanSchemaVersion')
    foreach ($name in $required) {
        if ($Approval.PSObject.Properties.Name -cnotcontains $name) { throw "Approval is missing required field '$name'." }
    }
    if ($Approval.SchemaVersion -cne $script:ApprovalSchemaVersion) { throw "Unsupported approval schema version '$($Approval.SchemaVersion)'." }
    if ($Approval.Decision -cne 'Approved') { throw 'Approval decision is not Approved.' }
    $approvalGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Approval.ApprovalId, [ref]$approvalGuid) -or $approvalGuid -eq [guid]::Empty) { throw 'ApprovalId must be a non-empty GUID.' }
    if ([string]$Approval.PlanId -cne [string]$Plan.PlanId) { throw 'Approval PlanId does not match the plan.' }
    if ([string]$Approval.PlanDigest -cne [string]$Plan.PlanDigest) { throw 'Approval PlanDigest does not match the plan.' }
    if ([string]::IsNullOrWhiteSpace([string]$Approval.Approver.Name) -or [string]::IsNullOrWhiteSpace([string]$Approval.Approver.Sid)) {
        throw 'Approval must identify the Windows approver by name and SID.'
    }
    $pairs = @(
        @{ Field = 'MachineId'; Expected = [string]$Plan.Machine.MachineId },
        @{ Field = 'ComputerName'; Expected = [string]$Plan.Machine.ComputerName },
        @{ Field = 'Scope'; Expected = [string]$Plan.Scope },
        @{ Field = 'ConfigurationFingerprint'; Expected = [string]$Plan.ConfigurationFingerprint },
        @{ Field = 'ManifestFingerprint'; Expected = [string]$Plan.ManifestFingerprint },
        @{ Field = 'PhoenixVersion'; Expected = [string]$Plan.PhoenixVersion },
        @{ Field = 'PlanSchemaVersion'; Expected = [string]$Plan.SchemaVersion }
    )
    foreach ($pair in $pairs) {
        if ([string]$Approval.($pair.Field) -cne $pair.Expected) { throw "Approval $($pair.Field) does not match the plan." }
    }
    $approvedAt = [datetimeoffset]::MinValue
    $expiresAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Approval.ApprovedAt, [ref]$approvedAt)) { throw 'ApprovedAt is invalid.' }
    if (-not [datetimeoffset]::TryParse([string]$Approval.ExpiresAt, [ref]$expiresAt)) { throw 'ExpiresAt is invalid.' }
    if ($approvedAt -gt $Now.AddMinutes(5)) { throw 'Approval timestamp is in the future.' }
    if ($expiresAt -le $approvedAt) { throw 'Approval expiry must be later than the approval timestamp.' }
    if ($Now -ge $expiresAt) { throw 'Approval has expired.' }
    if ($expiresAt -gt $approvedAt.AddHours(24)) { throw 'Approval validity cannot exceed 24 hours.' }
    return $true
}

function Test-PhoenixApprovalRecord {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    try { return [bool](Assert-PhoenixApprovalRecord -Plan $Plan -Approval $Approval -Now $Now) }
    catch { return $false }
}

Export-ModuleMember -Function ConvertTo-PhoenixCanonicalJson, Get-PhoenixDeploymentPlanDigest,
    New-PhoenixDeploymentPlanContract, Assert-PhoenixDeploymentPlanContract,
    Test-PhoenixDeploymentPlanContract, New-PhoenixApprovalRecord,
    Assert-PhoenixApprovalRecord, Test-PhoenixApprovalRecord
) {
        throw 'ApprovalPath must be a separate file ending in .approval.json.'
    }
    $fullApprovalPath = [IO.Path]::GetFullPath($ApprovalPath)
    if (Test-Path -LiteralPath $fullApprovalPath) { throw 'Refusing to overwrite an existing approval record. Choose a new approval path.' }
    if (-not (Test-PhoenixInteractiveSession)) { throw 'Approval denied: an interactive Windows ConsoleHost session is required.' }
    Write-Host ''
    Write-Host 'PHOENIX DEPLOYMENT PLAN APPROVAL' -ForegroundColor Cyan
    Write-Host "Plan ID: $($Plan.PlanId)"
    Write-Host "Machine: $($Plan.Machine.ComputerName) [$($Plan.Machine.MachineId)]"
    Write-Host "Scope: $($Plan.Scope)"
    Write-Host "Risk: $($Plan.Summary.Risk)"
    Write-Host "Actions: $(@($Plan.Actions).Count)"
    Write-Host "SHA-256: $($Plan.PlanDigest)"
    Write-Host 'Approval applies only to this exact plan and context.'
    $response = Read-Host 'Type APPROVE to create the approval record'
    if ($response -cne 'APPROVE') { throw 'Approval denied. No approval record was created.' }
    $approver = Get-PhoenixCurrentApproverIdentity
    $approvedAt = [datetimeoffset]::UtcNow
    $approval = [pscustomobject][ordered]@{
        SchemaVersion = $script:ApprovalSchemaVersion
        ApprovalId = [guid]::NewGuid().ToString('D')
        PlanId = [string]$Plan.PlanId
        PlanDigest = [string]$Plan.PlanDigest
        Decision = 'Approved'
        Approver = $approver
        ApprovedAt = $approvedAt.ToString('o')
        ExpiresAt = $approvedAt.AddHours($ValidityHours).ToString('o')
        MachineId = [string]$Plan.Machine.MachineId
        ComputerName = [string]$Plan.Machine.ComputerName
        Scope = [string]$Plan.Scope
        ConfigurationFingerprint = [string]$Plan.ConfigurationFingerprint
        ManifestFingerprint = [string]$Plan.ManifestFingerprint
        PhoenixVersion = [string]$Plan.PhoenixVersion
        PlanSchemaVersion = [string]$Plan.SchemaVersion
    }
    Assert-PhoenixApprovalRecord -Plan $Plan -Approval $approval | Out-Null
    $parent = Split-Path -Parent $ApprovalPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ConvertTo-PhoenixCanonicalJson -InputObject $approval
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ApprovalPath), $json, [Text.UTF8Encoding]::new($false))
    return $approval
}

function Assert-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    $required = @('SchemaVersion', 'ApprovalId', 'PlanId', 'PlanDigest', 'Decision', 'Approver',
        'ApprovedAt', 'ExpiresAt', 'MachineId', 'ComputerName', 'Scope',
        'ConfigurationFingerprint', 'ManifestFingerprint', 'PhoenixVersion', 'PlanSchemaVersion')
    foreach ($name in $required) {
        if ($Approval.PSObject.Properties.Name -cnotcontains $name) { throw "Approval is missing required field '$name'." }
    }
    if ($Approval.SchemaVersion -cne $script:ApprovalSchemaVersion) { throw "Unsupported approval schema version '$($Approval.SchemaVersion)'." }
    if ($Approval.Decision -cne 'Approved') { throw 'Approval decision is not Approved.' }
    $approvalGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Approval.ApprovalId, [ref]$approvalGuid) -or $approvalGuid -eq [guid]::Empty) { throw 'ApprovalId must be a non-empty GUID.' }
    if ([string]$Approval.PlanId -cne [string]$Plan.PlanId) { throw 'Approval PlanId does not match the plan.' }
    if ([string]$Approval.PlanDigest -cne [string]$Plan.PlanDigest) { throw 'Approval PlanDigest does not match the plan.' }
    if ([string]::IsNullOrWhiteSpace([string]$Approval.Approver.Name) -or [string]::IsNullOrWhiteSpace([string]$Approval.Approver.Sid)) {
        throw 'Approval must identify the Windows approver by name and SID.'
    }
    $pairs = @(
        @{ Field = 'MachineId'; Expected = [string]$Plan.Machine.MachineId },
        @{ Field = 'ComputerName'; Expected = [string]$Plan.Machine.ComputerName },
        @{ Field = 'Scope'; Expected = [string]$Plan.Scope },
        @{ Field = 'ConfigurationFingerprint'; Expected = [string]$Plan.ConfigurationFingerprint },
        @{ Field = 'ManifestFingerprint'; Expected = [string]$Plan.ManifestFingerprint },
        @{ Field = 'PhoenixVersion'; Expected = [string]$Plan.PhoenixVersion },
        @{ Field = 'PlanSchemaVersion'; Expected = [string]$Plan.SchemaVersion }
    )
    foreach ($pair in $pairs) {
        if ([string]$Approval.($pair.Field) -cne $pair.Expected) { throw "Approval $($pair.Field) does not match the plan." }
    }
    $approvedAt = [datetimeoffset]::MinValue
    $expiresAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Approval.ApprovedAt, [ref]$approvedAt)) { throw 'ApprovedAt is invalid.' }
    if (-not [datetimeoffset]::TryParse([string]$Approval.ExpiresAt, [ref]$expiresAt)) { throw 'ExpiresAt is invalid.' }
    if ($approvedAt -gt $Now.AddMinutes(5)) { throw 'Approval timestamp is in the future.' }
    if ($expiresAt -le $approvedAt) { throw 'Approval expiry must be later than the approval timestamp.' }
    if ($Now -ge $expiresAt) { throw 'Approval has expired.' }
    if ($expiresAt -gt $approvedAt.AddHours(24)) { throw 'Approval validity cannot exceed 24 hours.' }
    return $true
}

function Test-PhoenixApprovalRecord {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    try { return [bool](Assert-PhoenixApprovalRecord -Plan $Plan -Approval $Approval -Now $Now) }
    catch { return $false }
}

Export-ModuleMember -Function ConvertTo-PhoenixCanonicalJson, Get-PhoenixDeploymentPlanDigest,
    New-PhoenixDeploymentPlanContract, Assert-PhoenixDeploymentPlanContract,
    Test-PhoenixDeploymentPlanContract, New-PhoenixApprovalRecord,
    Assert-PhoenixApprovalRecord, Test-PhoenixApprovalRecord
) { throw 'ActionId must be a stable 1–128 character identifier.' }
        if (-not $ids.Add([string]$action.ActionId)) { throw "Duplicate ActionId '$($action.ActionId)'." }
        if ($action.Category -notin @('Application', 'Setting')) { throw "Unsupported action category '$($action.Category)'." }
        if ($action.Action -notin @('Install', 'Apply', 'Skip', 'Defer')) { throw "Unsupported action '$($action.Action)'." }
        if ($action.Action -eq 'Install' -and $action.Category -ne 'Application') { throw 'Install is only valid for Application actions.' }
        if ($action.Action -eq 'Apply' -and $action.Category -ne 'Setting') { throw 'Apply is only valid for Setting actions.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.Name)) { throw 'Action Name cannot be empty.' }
        if ([string]::IsNullOrWhiteSpace([string]$action.ManifestIdentity)) { throw "Action '$($action.ActionId)' is missing its manifest identity." }
        if ($action.Parameters -isnot [System.Collections.IDictionary] -and $action.Parameters -isnot [pscustomobject]) { throw "Action '$($action.ActionId)' Parameters must be an object." }
        if ([string]::IsNullOrWhiteSpace([string]$action.Reason)) { throw "Action '$($action.ActionId)' Reason cannot be empty." }
        if ($action.Risk -notin @('Low', 'Medium', 'High', 'Critical')) { throw "Action '$($action.ActionId)' has an unsupported Risk value." }
        if ($action.Order -isnot [ValueType] -or $action.Order -is [bool] -or [int]$action.Order -lt 0) { throw "Action '$($action.ActionId)' Order must be a non-negative integer." }
        if ($action.Dependencies -isnot [System.Collections.IEnumerable] -or $action.Dependencies -is [string]) { throw "Action '$($action.ActionId)' Dependencies must be an array." }
    }
    foreach ($action in @($Plan.Actions)) {
        foreach ($dependency in @($action.Dependencies)) {
            if ([string]$dependency -eq [string]$action.ActionId) { throw "Action '$($action.ActionId)' cannot depend on itself." }
            if (-not $ids.Contains([string]$dependency)) { throw "Action '$($action.ActionId)' references unknown dependency '$dependency'." }
        }
    }
    $actualDigest = Get-PhoenixDeploymentPlanDigest -Plan $Plan
    if ([string]$Plan.PlanDigest -cne $actualDigest) { throw 'PlanDigest does not match the canonical plan content.' }
    return $true
}

function Test-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][psobject]$Plan)
    try { return [bool](Assert-PhoenixDeploymentPlanContract -Plan $Plan) }
    catch { return $false }
}

function New-PhoenixDeploymentPlanContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Machine,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$PhoenixVersion,
        [Parameter(Mandatory)][AllowEmptyString()][string]$SourceRevision,
        [Parameter(Mandatory)][string]$ConfigurationFingerprint,
        [Parameter(Mandatory)][string]$ManifestFingerprint,
        [Parameter(Mandatory)][string]$StateFingerprint,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions,
        [Parameter(Mandatory)][psobject]$Summary,
        [string]$PlanId = ([guid]::NewGuid().ToString('D')),
        [datetimeoffset]$CreatedAt = [datetimeoffset]::UtcNow
    )
    $plan = [ordered]@{
        SchemaVersion = $script:PlanSchemaVersion
        PlanId = $PlanId
        CreatedAt = $CreatedAt.ToUniversalTime().ToString('o')
        PhoenixVersion = $PhoenixVersion
        SourceRevision = $SourceRevision
        Machine = $Machine
        Scope = $Scope
        ConfigurationFingerprint = $ConfigurationFingerprint.ToLowerInvariant()
        ManifestFingerprint = $ManifestFingerprint.ToLowerInvariant()
        StateFingerprint = $StateFingerprint.ToLowerInvariant()
        Actions = @($Actions)
        Summary = $Summary
        DigestAlgorithm = $script:DigestAlgorithm
        PlanDigest = ''
    }
    $result = [pscustomobject]$plan
    $result.PlanDigest = Get-PhoenixDeploymentPlanDigest -Plan $result
    Assert-PhoenixDeploymentPlanContract -Plan $result | Out-Null
    return $result
}

function Test-PhoenixInteractiveSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost')
}

function Get-PhoenixCurrentApproverIdentity {
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { throw 'Human plan approval is supported only from a Windows security context.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.Name) -or $null -eq $identity.User) {
        throw 'Could not resolve the current Windows approver identity.'
    }
    return [pscustomobject]@{ Name = $identity.Name; Sid = $identity.User.Value }
}

function New-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][string]$ApprovalPath,
        [ValidateRange(1, 24)][int]$ValidityHours = 4
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    if (-not (Test-PhoenixInteractiveSession)) { throw 'Approval denied: an interactive Windows ConsoleHost session is required.' }
    Write-Host ''
    Write-Host 'PHOENIX DEPLOYMENT PLAN APPROVAL' -ForegroundColor Cyan
    Write-Host "Plan ID: $($Plan.PlanId)"
    Write-Host "Machine: $($Plan.Machine.ComputerName) [$($Plan.Machine.MachineId)]"
    Write-Host "Scope: $($Plan.Scope)"
    Write-Host "Risk: $($Plan.Summary.Risk)"
    Write-Host "Actions: $(@($Plan.Actions).Count)"
    Write-Host "SHA-256: $($Plan.PlanDigest)"
    Write-Host 'Approval applies only to this exact plan and context.'
    $response = Read-Host 'Type APPROVE to create the approval record'
    if ($response -cne 'APPROVE') { throw 'Approval denied. No approval record was created.' }
    $approver = Get-PhoenixCurrentApproverIdentity
    $approvedAt = [datetimeoffset]::UtcNow
    $approval = [pscustomobject][ordered]@{
        SchemaVersion = $script:ApprovalSchemaVersion
        ApprovalId = [guid]::NewGuid().ToString('D')
        PlanId = [string]$Plan.PlanId
        PlanDigest = [string]$Plan.PlanDigest
        Decision = 'Approved'
        Approver = $approver
        ApprovedAt = $approvedAt.ToString('o')
        ExpiresAt = $approvedAt.AddHours($ValidityHours).ToString('o')
        MachineId = [string]$Plan.Machine.MachineId
        ComputerName = [string]$Plan.Machine.ComputerName
        Scope = [string]$Plan.Scope
        ConfigurationFingerprint = [string]$Plan.ConfigurationFingerprint
        ManifestFingerprint = [string]$Plan.ManifestFingerprint
        PhoenixVersion = [string]$Plan.PhoenixVersion
        PlanSchemaVersion = [string]$Plan.SchemaVersion
    }
    Assert-PhoenixApprovalRecord -Plan $Plan -Approval $approval | Out-Null
    $parent = Split-Path -Parent $ApprovalPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ConvertTo-PhoenixCanonicalJson -InputObject $approval
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ApprovalPath), $json, [Text.UTF8Encoding]::new($false))
    return $approval
}

function Assert-PhoenixApprovalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
    $required = @('SchemaVersion', 'ApprovalId', 'PlanId', 'PlanDigest', 'Decision', 'Approver',
        'ApprovedAt', 'ExpiresAt', 'MachineId', 'ComputerName', 'Scope',
        'ConfigurationFingerprint', 'ManifestFingerprint', 'PhoenixVersion', 'PlanSchemaVersion')
    foreach ($name in $required) {
        if ($Approval.PSObject.Properties.Name -cnotcontains $name) { throw "Approval is missing required field '$name'." }
    }
    if ($Approval.SchemaVersion -cne $script:ApprovalSchemaVersion) { throw "Unsupported approval schema version '$($Approval.SchemaVersion)'." }
    if ($Approval.Decision -cne 'Approved') { throw 'Approval decision is not Approved.' }
    $approvalGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Approval.ApprovalId, [ref]$approvalGuid) -or $approvalGuid -eq [guid]::Empty) { throw 'ApprovalId must be a non-empty GUID.' }
    if ([string]$Approval.PlanId -cne [string]$Plan.PlanId) { throw 'Approval PlanId does not match the plan.' }
    if ([string]$Approval.PlanDigest -cne [string]$Plan.PlanDigest) { throw 'Approval PlanDigest does not match the plan.' }
    if ([string]::IsNullOrWhiteSpace([string]$Approval.Approver.Name) -or [string]::IsNullOrWhiteSpace([string]$Approval.Approver.Sid)) {
        throw 'Approval must identify the Windows approver by name and SID.'
    }
    $pairs = @(
        @{ Field = 'MachineId'; Expected = [string]$Plan.Machine.MachineId },
        @{ Field = 'ComputerName'; Expected = [string]$Plan.Machine.ComputerName },
        @{ Field = 'Scope'; Expected = [string]$Plan.Scope },
        @{ Field = 'ConfigurationFingerprint'; Expected = [string]$Plan.ConfigurationFingerprint },
        @{ Field = 'ManifestFingerprint'; Expected = [string]$Plan.ManifestFingerprint },
        @{ Field = 'PhoenixVersion'; Expected = [string]$Plan.PhoenixVersion },
        @{ Field = 'PlanSchemaVersion'; Expected = [string]$Plan.SchemaVersion }
    )
    foreach ($pair in $pairs) {
        if ([string]$Approval.($pair.Field) -cne $pair.Expected) { throw "Approval $($pair.Field) does not match the plan." }
    }
    $approvedAt = [datetimeoffset]::MinValue
    $expiresAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Approval.ApprovedAt, [ref]$approvedAt)) { throw 'ApprovedAt is invalid.' }
    if (-not [datetimeoffset]::TryParse([string]$Approval.ExpiresAt, [ref]$expiresAt)) { throw 'ExpiresAt is invalid.' }
    if ($approvedAt -gt $Now.AddMinutes(5)) { throw 'Approval timestamp is in the future.' }
    if ($expiresAt -le $approvedAt) { throw 'Approval expiry must be later than the approval timestamp.' }
    if ($Now -ge $expiresAt) { throw 'Approval has expired.' }
    if ($expiresAt -gt $approvedAt.AddHours(24)) { throw 'Approval validity cannot exceed 24 hours.' }
    return $true
}

function Test-PhoenixApprovalRecord {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][psobject]$Approval,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    try { return [bool](Assert-PhoenixApprovalRecord -Plan $Plan -Approval $Approval -Now $Now) }
    catch { return $false }
}

Export-ModuleMember -Function ConvertTo-PhoenixCanonicalJson, Get-PhoenixDeploymentPlanDigest,
    New-PhoenixDeploymentPlanContract, Assert-PhoenixDeploymentPlanContract,
    Test-PhoenixDeploymentPlanContract, New-PhoenixApprovalRecord,
    Assert-PhoenixApprovalRecord, Test-PhoenixApprovalRecord
