<#
    Phoenix Plan Freshness Gate (PHX-005B, ADR 0019).

    Produces the provenance the PHX-005A plan contract requires (machine
    identity, configuration / manifest / state fingerprints, stable action IDs
    and per-action manifest identities), builds a contract plan from the
    existing Deployment Planner, and decides whether an approved plan is still
    fresh: the same plan, rebuilt now for the same scope, must match it.

    Read-only. Nothing here installs, applies, executes or rolls back. Current
    state comes from the State Engine and plan decisions from the Deployment
    Planner - neither is reimplemented, and neither changes behaviour
    (Outdated is still planned as Skip).

    Fails closed: any check that cannot be evaluated makes the plan stale.

    Operator-invoked (no module.json), so normal orchestration never discovers
    it. Depends on PhoenixLogging being imported first.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\PlanContracts\PlanContracts.psd1')
Import-Module (Join-Path $PSScriptRoot '..\PhoenixCore\PhoenixCore.psd1')
Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\StateEngine\StateEngine.psd1')
Import-Module (Join-Path $PSScriptRoot '..\DeploymentPlanner\DeploymentPlanner.psd1')

# Every declaration that can change what a plan means. Choice (a) in the
# PHX-005B design: all manifests and profiles, not only those in scope -
# stricter, and it cannot miss a dependency.
$script:ManifestSources = @(
    [PSCustomObject]@{ Category = 'Application'; RelativePath = 'modules/Installer/Applications' }
    [PSCustomObject]@{ Category = 'Setting'; RelativePath = 'modules/WindowsConfig/Settings' }
    [PSCustomObject]@{ Category = 'Profile'; RelativePath = 'profiles' }
)

# Action fields compared for freshness. Reason and Risk are explanation, not
# execution semantics: a reworded reason must not make a plan stale.
$script:SemanticActionFields = @('ActionId', 'Category', 'Name', 'Action', 'ManifestIdentity', 'Parameters', 'Dependencies', 'Order')

function Get-PhoenixSha256Hex {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-PhoenixCanonicalHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)
    return Get-PhoenixSha256Hex -Text (ConvertTo-PhoenixCanonicalJson -InputObject $InputObject)
}

function ConvertTo-PhoenixActionId {
    <#
        .SYNOPSIS
        Stable action ID from category and name, e.g. 'application:epic-games-launcher'.
        Collisions are not resolved here - the plan contract rejects duplicate IDs.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name
    )
    $slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrEmpty($slug)) { throw "Cannot derive an action ID from name '$Name'." }
    return "$($Category.ToLowerInvariant()):$slug"
}

function ConvertFrom-PhoenixPlanScope {
    <#
        .SYNOPSIS
        Maps a plan Scope label (as produced by Get-PhoenixState) back to the
        planner's -ProfileName. Unknown labels are rejected, never guessed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Scope)
    if ($Scope -ceq 'Configuration') { return '' }
    if ($Scope -cmatch '^Profile: (.+)$') { return $Matches[1] }
    throw "Unrecognised plan scope '$Scope'. Expected 'Configuration' or 'Profile: <name>'."
}

function Get-PhoenixSourceRevision {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RootPath)
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if (-not $git) { return '' }
    $revision = & $git.Source -C $RootPath rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$revision)) { return '' }
    return ([string]$revision).Trim()
}

function Get-PhoenixMachineIdentity {
    <#
        .SYNOPSIS
        The machine binding for plans and approvals: Windows MachineGuid plus
        computer name. Throws if either cannot be read - never guessed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    if (-not $IsWindows) { throw 'Machine identity is only available on Windows.' }
    try {
        $machineGuid = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop
    }
    catch {
        throw "Could not read the Windows MachineGuid: $($_.Exception.Message)"
    }
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse([string]$machineGuid, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw 'The Windows MachineGuid is missing or not a valid GUID.'
    }
    $computerName = [Environment]::MachineName
    if ([string]::IsNullOrWhiteSpace($computerName)) { throw 'Could not read the computer name.' }
    return [PSCustomObject]@{ MachineId = $parsed.ToString('D'); ComputerName = $computerName }
}

function Get-PhoenixConfigurationFingerprint {
    <#
        .SYNOPSIS
        SHA-256 of the merged Phoenix configuration in canonical form.
        Whitespace and key order do not change it; any value change does.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RootPath)
    return Get-PhoenixCanonicalHash -InputObject (Get-PhoenixConfiguration -RootPath $RootPath)
}

function Get-PhoenixManifestFingerprint {
    <#
        .SYNOPSIS
        Fingerprints every application manifest, setting manifest and profile,
        and returns the per-item identities used as action ManifestIdentity.

        .DESCRIPTION
        Each file is parsed and hashed in canonical form, so formatting-only
        edits do not change it. The overall fingerprint covers every file's
        relative path and hash. Identities are keyed '<Category>/<Name>' and
        carry the relative path and hash of the declaring file.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$RootPath)

    $files = [System.Collections.Generic.List[object]]::new()
    $identities = @{}
    foreach ($source in $script:ManifestSources) {
        $directory = Join-Path $RootPath $source.RelativePath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Manifest directory not found: $($source.RelativePath)"
        }
        $entries = @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name -CaseSensitive)
        foreach ($entry in $entries) {
            $relativePath = "$($source.RelativePath)/$($entry.Name)"
            $content = ConvertFrom-PhoenixContractJson -Json ([IO.File]::ReadAllText($entry.FullName))
            $hash = Get-PhoenixCanonicalHash -InputObject $content
            $files.Add([ordered]@{ Path = $relativePath; Sha256 = $hash })

            if ($source.Category -ne 'Profile') {
                if ($null -eq $content -or $content.PSObject.Properties.Name -cnotcontains 'Name' -or [string]::IsNullOrWhiteSpace([string]$content.Name)) {
                    throw "Manifest '$relativePath' has no Name."
                }
                $key = "$($source.Category)/$($content.Name)"
                if ($identities.ContainsKey($key)) { throw "Duplicate manifest identity '$key' in '$relativePath'." }
                $identities[$key] = [PSCustomObject]@{
                    Identity     = "$key#sha256:$hash"
                    RelativePath = $relativePath
                    Sha256       = $hash
                }
            }
        }
    }

    return [PSCustomObject]@{
        Fingerprint = Get-PhoenixCanonicalHash -InputObject @($files.ToArray())
        Identities  = $identities
    }
}

function Get-PhoenixStateFingerprint {
    <#
        .SYNOPSIS
        SHA-256 over the semantic state: scope, elevation, preflight safety
        and each in-scope item's category, name and status. Timestamps and
        hardware detail are excluded so they cannot cause false stale results.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$State,
        [Parameter(Mandatory)][bool]$Elevated,
        [Parameter(Mandatory)][bool]$PreflightSafe
    )
    $items = @(@($State.Applications) + @($State.Settings) |
        Where-Object { $null -ne $_ } |
        ForEach-Object { [ordered]@{ Category = [string]$_.Category; Name = [string]$_.Name; Status = [string]$_.Status } } |
        Sort-Object -Property @{ Expression = { $_.Category } }, @{ Expression = { $_.Name } } -CaseSensitive)
    return Get-PhoenixCanonicalHash -InputObject ([ordered]@{
        Scope         = [string]$State.Scope
        Elevated      = $Elevated
        PreflightSafe = $PreflightSafe
        Items         = @($items)
    })
}

function New-PhoenixContractPlan {
    <#
        .SYNOPSIS
        Builds a PHX-005A contract plan for the current machine from the
        existing Deployment Planner and State Engine. Read-only.

        .DESCRIPTION
        Planner decisions (Install/Apply/Skip/Defer, reason, risk, order) are
        carried over unchanged. This adds the provenance the contract needs:
        machine identity, Phoenix version and source revision, configuration,
        manifest and state fingerprints, stable action IDs, manifest
        identities, manifest-path parameters and dependency IDs.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string]$ProfileName,
        [string]$PlanId,
        [datetimeoffset]$CreatedAt = [datetimeoffset]::UtcNow
    )

    $machine = Get-PhoenixMachineIdentity
    $phoenixVersion = (Get-PhoenixVersion -RootPath $RootPath).Version
    $sourceRevision = Get-PhoenixSourceRevision -RootPath $RootPath
    $configurationFingerprint = Get-PhoenixConfigurationFingerprint -RootPath $RootPath
    $manifests = Get-PhoenixManifestFingerprint -RootPath $RootPath

    $plannerPlan = New-PhoenixDeploymentPlan -RootPath $RootPath -ProfileName $ProfileName
    $state = Get-PhoenixState -RootPath $RootPath -ProfileName $ProfileName -SkipVersionCheck
    if ([string]$state.Scope -cne [string]$plannerPlan.Scope) {
        throw "State scope '$($state.Scope)' does not match planner scope '$($plannerPlan.Scope)'."
    }
    $stateFingerprint = Get-PhoenixStateFingerprint -State $state -Elevated ([bool]$plannerPlan.Elevated) -PreflightSafe ([bool]$plannerPlan.PreflightSafe)

    # Application dependencies are declared by name in the manifests.
    $applicationDependencies = @{}
    foreach ($item in @($state.Applications)) {
        if ($null -eq $item) { continue }
        $declared = @()
        if ($item.Manifest -and $item.Manifest.PSObject.Properties.Name -contains 'Dependencies' -and $null -ne $item.Manifest.Dependencies) {
            $declared = @($item.Manifest.Dependencies)
        }
        $applicationDependencies[[string]$item.Name] = $declared
    }

    $actionIdByName = @{}
    foreach ($plannerAction in @($plannerPlan.Actions)) {
        $actionIdByName["$($plannerAction.Category)/$($plannerAction.Name)"] = ConvertTo-PhoenixActionId -Category $plannerAction.Category -Name $plannerAction.Name
    }

    $actions = [System.Collections.Generic.List[object]]::new()
    $order = 0
    foreach ($plannerAction in @($plannerPlan.Actions)) {
        $key = "$($plannerAction.Category)/$($plannerAction.Name)"
        if (-not $manifests.Identities.ContainsKey($key)) {
            throw "No manifest identity found for planned $($plannerAction.Category.ToLowerInvariant()) '$($plannerAction.Name)'."
        }
        $identity = $manifests.Identities[$key]

        $dependencyIds = [System.Collections.Generic.List[string]]::new()
        if ($plannerAction.Category -eq 'Application' -and $applicationDependencies.ContainsKey([string]$plannerAction.Name)) {
            foreach ($dependencyName in $applicationDependencies[[string]$plannerAction.Name]) {
                $dependencyKey = "Application/$dependencyName"
                if (-not $actionIdByName.ContainsKey($dependencyKey)) {
                    throw "Application '$($plannerAction.Name)' depends on '$dependencyName', which is not in the plan scope."
                }
                $dependencyIds.Add($actionIdByName[$dependencyKey])
            }
        }

        $actions.Add([PSCustomObject][ordered]@{
            ActionId         = $actionIdByName[$key]
            Category         = [string]$plannerAction.Category
            Name             = [string]$plannerAction.Name
            ManifestIdentity = $identity.Identity
            Action           = [string]$plannerAction.Action
            Parameters       = [ordered]@{ ManifestPath = $identity.RelativePath }
            Reason           = [string]$plannerAction.Reason
            Risk             = [string]$plannerAction.Risk
            Order            = $order
            Dependencies     = @($dependencyIds.ToArray())
        })
        $order++
    }

    $hardware = [ordered]@{}
    foreach ($property in $plannerPlan.Machine.PSObject.Properties) {
        if ($property.Name -ne 'ComputerName') { $hardware[$property.Name] = $property.Value }
    }

    $summary = [ordered]@{}
    foreach ($property in $plannerPlan.Summary.PSObject.Properties) { $summary[$property.Name] = $property.Value }
    $summary['Elevated'] = [bool]$plannerPlan.Elevated
    $summary['PreflightSafe'] = [bool]$plannerPlan.PreflightSafe

    $contractArguments = @{
        Machine                  = [ordered]@{ MachineId = $machine.MachineId; ComputerName = $machine.ComputerName; Hardware = $hardware }
        Scope                    = [string]$plannerPlan.Scope
        PhoenixVersion           = [string]$phoenixVersion
        SourceRevision           = $sourceRevision
        ConfigurationFingerprint = $configurationFingerprint
        ManifestFingerprint      = $manifests.Fingerprint
        StateFingerprint         = $stateFingerprint
        Actions                  = @($actions.ToArray())
        Summary                  = [PSCustomObject]$summary
        CreatedAt                = $CreatedAt
    }
    if ($PlanId) { $contractArguments['PlanId'] = $PlanId }
    return New-PhoenixDeploymentPlanContract @contractArguments
}

function New-PhoenixFreshnessCheck {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    return [PSCustomObject]@{ Name = $Name; Passed = $Passed; Detail = $Detail }
}

function Compare-PhoenixPlanActions {
    <#
        .SYNOPSIS
        Compares the semantic action sets of two plans by ActionId and returns
        a description of every difference (empty when they match).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Approved,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Current
    )
    $project = {
        param($Action)
        $semantic = [ordered]@{}
        foreach ($field in $script:SemanticActionFields) { $semantic[$field] = $Action.$field }
        ConvertTo-PhoenixCanonicalJson -InputObject $semantic
    }
    $approvedById = [ordered]@{}
    foreach ($action in $Approved) { $approvedById[[string]$action.ActionId] = $action }
    $currentById = [ordered]@{}
    foreach ($action in $Current) { $currentById[[string]$action.ActionId] = $action }

    $differences = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $approvedById.Keys) {
        if (-not $currentById.Contains($id)) { $differences.Add("'$id' is no longer planned."); continue }
        $approvedAction = $approvedById[$id]
        $currentAction = $currentById[$id]
        if ((& $project $approvedAction) -cne (& $project $currentAction)) {
            $changed = @($script:SemanticActionFields | Where-Object {
                (ConvertTo-PhoenixCanonicalJson -InputObject $approvedAction.$_) -cne (ConvertTo-PhoenixCanonicalJson -InputObject $currentAction.$_)
            })
            $detail = if ($changed -contains 'Action') { " (approved $($approvedAction.Action), now $($currentAction.Action))" } else { '' }
            $differences.Add("'$id' changed: $($changed -join ', ')$detail.")
        }
    }
    foreach ($id in $currentById.Keys) {
        if (-not $approvedById.Contains($id)) { $differences.Add("'$id' is newly planned ($($currentById[$id].Action)).") }
    }
    return $differences.ToArray()
}

function Test-PhoenixPlanFreshness {
    <#
        .SYNOPSIS
        Decides whether an approved plan is still fresh for this machine.
        Returns a result with per-check detail; never throws.

        .DESCRIPTION
        Validates the plan contract, then rebuilds the plan now for the same
        scope and compares: machine identity, Phoenix version, configuration,
        manifest and state fingerprints, and the semantic action set (IDs,
        actions, manifest identities, parameters, dependencies, order).
        Fresh is true only when every check passes. Any check that cannot be
        evaluated fails, so unknown freshness is never treated as safe.
        Source revision differences are reported for information only.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Plan,
        [Parameter(Mandatory)][string]$RootPath
    )

    $checks = [System.Collections.Generic.List[PSCustomObject]]::new()
    $currentPlan = $null
    $planId = $null
    $planDigest = $null
    try { $planId = [string]$Plan.PlanId; $planDigest = [string]$Plan.PlanDigest } catch { $planId = $null }

    $result = {
        $failed = @($checks | Where-Object { -not $_.Passed })
        [PSCustomObject]@{
            Fresh        = ($checks.Count -gt 0 -and $failed.Count -eq 0)
            PlanId       = $planId
            PlanDigest   = $planDigest
            CheckedAt    = [datetimeoffset]::UtcNow.ToString('o')
            Checks       = $checks.ToArray()
            FailedChecks = @($failed | ForEach-Object Name)
            CurrentPlan  = $currentPlan
        }
    }

    try {
        Assert-PhoenixDeploymentPlanContract -Plan $Plan | Out-Null
        $checks.Add((New-PhoenixFreshnessCheck -Name 'PlanContract' -Passed $true -Detail 'Schema, actions and digest are valid.'))
    }
    catch {
        $checks.Add((New-PhoenixFreshnessCheck -Name 'PlanContract' -Passed $false -Detail $_.Exception.Message))
        return (& $result)
    }

    try {
        $profileName = ConvertFrom-PhoenixPlanScope -Scope ([string]$Plan.Scope)
        $checks.Add((New-PhoenixFreshnessCheck -Name 'Scope' -Passed $true -Detail "Scope '$($Plan.Scope)' recognised."))
    }
    catch {
        $checks.Add((New-PhoenixFreshnessCheck -Name 'Scope' -Passed $false -Detail $_.Exception.Message))
        return (& $result)
    }

    try {
        $currentPlan = New-PhoenixContractPlan -RootPath $RootPath -ProfileName $profileName
    }
    catch {
        $checks.Add((New-PhoenixFreshnessCheck -Name 'Evaluation' -Passed $false -Detail "Could not rebuild the plan for comparison: $($_.Exception.Message)"))
        return (& $result)
    }

    $sameMachineId = [string]$Plan.Machine.MachineId -ceq [string]$currentPlan.Machine.MachineId
    $sameComputer = [string]$Plan.Machine.ComputerName -ceq [string]$currentPlan.Machine.ComputerName
    $machineDetail = if ($sameMachineId -and $sameComputer) { 'Same machine.' } else {
        "Approved for $($Plan.Machine.ComputerName) [$($Plan.Machine.MachineId)], running on $($currentPlan.Machine.ComputerName) [$($currentPlan.Machine.MachineId)]."
    }
    $checks.Add((New-PhoenixFreshnessCheck -Name 'MachineIdentity' -Passed ($sameMachineId -and $sameComputer) -Detail $machineDetail))

    foreach ($field in @('PhoenixVersion', 'ConfigurationFingerprint', 'ManifestFingerprint', 'StateFingerprint')) {
        $same = [string]$Plan.$field -ceq [string]$currentPlan.$field
        $detail = if ($same) { 'Unchanged.' } else { "Approved '$($Plan.$field)', now '$($currentPlan.$field)'." }
        $checks.Add((New-PhoenixFreshnessCheck -Name $field -Passed $same -Detail $detail))
    }

    $differences = @(Compare-PhoenixPlanActions -Approved @($Plan.Actions) -Current @($currentPlan.Actions))
    $actionDetail = if ($differences.Count -eq 0) { "All $(@($Plan.Actions).Count) action(s) unchanged." } else { $differences -join ' ' }
    $checks.Add((New-PhoenixFreshnessCheck -Name 'ActionSet' -Passed ($differences.Count -eq 0) -Detail $actionDetail))

    $outcome = & $result
    $sourceNote = if ([string]$Plan.SourceRevision -ceq [string]$currentPlan.SourceRevision) { 'Unchanged.' } else {
        "Informational: plan built at '$($Plan.SourceRevision)', current '$($currentPlan.SourceRevision)'."
    }
    $outcome | Add-Member -NotePropertyName SourceRevisionNote -NotePropertyValue $sourceNote
    return $outcome
}

function Assert-PhoenixPlanFreshness {
    <#
        .SYNOPSIS
        Throws unless the plan is fresh; returns the freshness result when it is.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Plan,
        [Parameter(Mandatory)][string]$RootPath
    )
    $freshness = Test-PhoenixPlanFreshness -Plan $Plan -RootPath $RootPath
    if (-not $freshness.Fresh) {
        $reasons = @($freshness.Checks | Where-Object { -not $_.Passed } | ForEach-Object { "$($_.Name): $($_.Detail)" }) -join ' | '
        Write-PhoenixLog -Level ERROR -Message "[PlanFreshness] Plan $($freshness.PlanId) is stale - create and approve a new plan. $reasons"
        throw "Plan is stale and cannot be executed. Create and approve a new plan. $reasons"
    }
    Write-PhoenixLog -Level INFO -Message "[PlanFreshness] Plan $($freshness.PlanId) is fresh."
    return $freshness
}

Export-ModuleMember -Function Get-PhoenixMachineIdentity, Get-PhoenixConfigurationFingerprint,
    Get-PhoenixManifestFingerprint, Get-PhoenixStateFingerprint, New-PhoenixContractPlan,
    Test-PhoenixPlanFreshness, Assert-PhoenixPlanFreshness
