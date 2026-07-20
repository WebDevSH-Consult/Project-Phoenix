<#
    Phoenix Desired State & Drift Management Engine (ADR 0018, PHX-004).

    The single source of truth for current-vs-desired state. Phoenix's other
    engines deploy; this one lets Phoenix *maintain* - detect when a machine
    has drifted from what Phoenix declared, and (in a later slice) repair only
    the drift.

    Desired state = the manifests in scope (config- or profile-selected), just
    as DSC/Puppet/Chef derive from declared configuration. This module
    orchestrates the existing predicates into a state model; it reimplements no
    check. Honest drift surface (ADR 0018): application presence, application
    version currency (WinGet), and registry settings. Drivers and services are
    out of scope until their manifest capabilities exist.

    Slice 1: Get-PhoenixState, Compare-PhoenixState, Invoke-PhoenixAudit -
    all read-only. Slice 2: Invoke-PhoenixRepair - re-apply desired state for
    ONLY the drifted items, through the existing idempotent apply/install/
    upgrade functions.

    Operator-invoked (the maintain path), not an orchestrated forward stage -
    no module.json. Depends on PhoenixLogging; imports the capability modules
    it consumes itself.
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1')
Import-Module (Join-Path $PSScriptRoot '..\WindowsConfig\WindowsConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Installer\Installer.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Recovery\Recovery.psd1')

# The conforming (no-drift) status for each category.
$script:ConformingApplicationStatus = 'Present'
$script:ConformingSettingStatus = 'Applied'

function Get-PhoenixState {
    <#
        .SYNOPSIS
        Builds the machine's current-state model for every in-scope application
        and setting, evaluated against its declaration.

        .DESCRIPTION
        Applications are scoped by -ProfileName (expanded with dependencies) or,
        without it, by configuration (ConfigFlag); settings by configuration -
        the same scoping the Deployment Planner uses. Each item's Status is its
        observed state relative to desired: applications are Missing (declared,
        not installed), Outdated (installed, newer available), or Present;
        settings are Modified (value != desired) or Applied. Read-only - uses
        the existing predicates, changes nothing.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ProfileName
    )

    $configuration = Get-PhoenixConfiguration -RootPath $RootPath
    $appManifests = @(Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $RootPath 'modules\Installer\Applications'))
    $settingManifests = @(Get-PhoenixSettingManifest -ManifestsPath (Join-Path $RootPath 'modules\WindowsConfig\Settings'))

    if ($ProfileName) {
        $workstationProfile = Get-PhoenixProfile -ProfilesPath (Join-Path $RootPath 'profiles') -ProfileName $ProfileName
        $scopedApps = @(Expand-PhoenixProfileApplications -Manifests $appManifests -ApplicationNames $workstationProfile.Applications)
        $scopeLabel = "Profile: $($workstationProfile.Name)"
    }
    else {
        $scopedApps = @($appManifests | Where-Object { Get-PhoenixConfigValue -Configuration $configuration -Path $_.ConfigFlag })
        $scopeLabel = 'Configuration'
    }

    $scopedSettings = @($settingManifests | Where-Object { Get-PhoenixConfigValue -Configuration $configuration -Path $_.ConfigFlag })

    $applications = foreach ($manifest in $scopedApps) {
        if (-not (Test-PhoenixApplicationSatisfied -Manifest $manifest)) {
            $status = 'Missing'
        }
        elseif (Test-PhoenixApplicationOutdated -Manifest $manifest) {
            $status = 'Outdated'
        }
        else {
            $status = 'Present'
        }
        [PSCustomObject]@{ Category = 'Application'; Name = $manifest.Name; Status = $status; Manifest = $manifest }
    }

    $settings = foreach ($manifest in $scopedSettings) {
        $status = if (Test-PhoenixSettingApplied -Manifest $manifest) { 'Applied' } else { 'Modified' }
        [PSCustomObject]@{ Category = 'Setting'; Name = $manifest.Name; Status = $status; Manifest = $manifest }
    }

    return [PSCustomObject]@{
        Timestamp    = (Get-Date).ToString('o')
        ComputerName = [System.Environment]::MachineName
        Scope        = $scopeLabel
        Applications = @($applications)
        Settings     = @($settings)
    }
}

function Compare-PhoenixState {
    <#
        .SYNOPSIS
        Returns the drift set from a state model - only the items that do not
        conform to their declaration, each tagged with a drift type and the
        manifest needed to repair it.

        .DESCRIPTION
        Pure function over the state model (no I/O): an application that is
        Missing or Outdated, or a setting that is Modified, is drift. Everything
        conforming is omitted. The DriftType (Missing / Outdated / Modified) and
        the manifest are carried through so a later repair can act on exactly
        the drift and nothing else.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State
    )

    $drift = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in @($State.Applications)) {
        if ($item.Status -ne $script:ConformingApplicationStatus) {
            $drift.Add([PSCustomObject]@{ Category = 'Application'; Name = $item.Name; DriftType = $item.Status; Manifest = $item.Manifest })
        }
    }
    foreach ($item in @($State.Settings)) {
        if ($item.Status -ne $script:ConformingSettingStatus) {
            $drift.Add([PSCustomObject]@{ Category = 'Setting'; Name = $item.Name; DriftType = $item.Status; Manifest = $item.Manifest })
        }
    }

    $driftArray = $drift.ToArray()
    return [PSCustomObject]@{
        Timestamp    = $State.Timestamp
        ComputerName = $State.ComputerName
        Scope        = $State.Scope
        InDrift      = ($driftArray.Count -gt 0)
        Drift        = $driftArray
        Summary      = [PSCustomObject]@{
            Missing  = @($driftArray | Where-Object DriftType -eq 'Missing').Count
            Outdated = @($driftArray | Where-Object DriftType -eq 'Outdated').Count
            Modified = @($driftArray | Where-Object DriftType -eq 'Modified').Count
            Total    = $driftArray.Count
        }
    }
}

function Invoke-PhoenixAudit {
    <#
        .SYNOPSIS
        Audits the machine for drift: builds the current state, compares it to
        desired, renders a summary, and writes a JSON artifact. Changes nothing.

        .DESCRIPTION
        The read-only "here is exactly what has drifted" report (ADR 0018). The
        JSON lands under audits/ (gitignored, like reports/ and plans/). Returns
        the drift object so callers (and a future Invoke-PhoenixRepair) can act
        on it.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ProfileName,

        [string]$AuditsPath = (Join-Path $RootPath 'audits')
    )

    $state = Get-PhoenixState -RootPath $RootPath -ProfileName $ProfileName
    $drift = Compare-PhoenixState -State $state

    Write-Host ''
    Write-Host "Phoenix Drift Audit - $($drift.Scope)" -ForegroundColor Cyan
    Write-Host "  Machine: $($drift.ComputerName)    $($drift.Timestamp)"
    Write-Host ''

    if (-not $drift.InDrift) {
        Write-Host '  No drift detected - the machine matches its declared state.' -ForegroundColor Green
    }
    else {
        foreach ($item in $drift.Drift) {
            $colour = if ($item.DriftType -eq 'Outdated') { 'Yellow' } else { 'Red' }
            Write-Host ("  [{0,-8}] {1,-11} {2}" -f $item.DriftType, $item.Category, $item.Name) -ForegroundColor $colour
        }
    }

    Write-Host ''
    $s = $drift.Summary
    Write-Host "  Drift: $($s.Total) item(s) - $($s.Missing) missing, $($s.Outdated) outdated, $($s.Modified) modified" -ForegroundColor $(if ($drift.InDrift) { 'Yellow' } else { 'Green' })
    Write-Host ''

    if (-not (Test-Path -LiteralPath $AuditsPath)) {
        New-Item -ItemType Directory -Path $AuditsPath -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $AuditsPath "drift-audit-$stamp.json"
    # Depth 6 keeps the nested manifests readable in the artifact.
    $drift | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8
    Write-PhoenixLog -Level SUCCESS -Message "[StateEngine] Drift audit written: $path ($($drift.Summary.Total) drift item(s))."

    return $drift
}

function Invoke-PhoenixRepair {
    <#
        .SYNOPSIS
        Repairs drift: re-applies desired state for ONLY the items that have
        drifted, through the existing idempotent apply/install/upgrade
        functions. Never a profile redeploy.

        .DESCRIPTION
        Audits for drift, then repairs each drifted item and nothing else -
        a Missing application is installed, an Outdated one upgraded, a
        Modified setting re-applied. Every repair reuses the module that owns
        that change (Install-PhoenixApplication, Update-PhoenixApplication,
        Set-PhoenixSetting), so each is idempotent and self-verifying; this
        function adds selection and ordering, not new mutation logic.

        Settings are repaired before applications (forward deployment order).
        Application repairs are gated by the installer preflight (ADR 0012) -
        nothing installs on a non-idle servicing state - while setting repairs
        proceed regardless, since a registry write is not an installation.
        Elevation is handled inside Set-PhoenixSetting (WARN-skip, ADR 0013).

        -DryRun previews the repairs without invoking any backend. With
        -Transactional, a failed repair reverses the repairs that changed
        (via the Recovery engine, ADR 0017). Note that a *version* repair is
        not reversible - Update-PhoenixApplication reports no Changed flag,
        because undoing an upgrade by uninstalling would destroy an
        application that was legitimately installed before the repair.

        .EXAMPLE
        Invoke-PhoenixRepair -RootPath (Get-Location) -DryRun
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ProfileName,

        [switch]$DryRun,

        [switch]$Transactional,

        [switch]$SkipPreflight
    )

    $state = Get-PhoenixState -RootPath $RootPath -ProfileName $ProfileName
    $drift = Compare-PhoenixState -State $state

    if (-not $drift.InDrift) {
        Write-PhoenixLog -Level SUCCESS -Message '[StateEngine] No drift detected - nothing to repair.'
        return @()
    }

    # Forward order: settings first, then applications.
    $settingDrift = @($drift.Drift | Where-Object Category -eq 'Setting')
    $appDrift = @($drift.Drift | Where-Object Category -eq 'Application')

    Write-PhoenixLog -Level INFO -Message "[StateEngine] Repairing $($drift.Summary.Total) drifted item(s): $($settingDrift.Count) setting(s), $($appDrift.Count) application(s)."

    # Preflight gates application repairs only (ADR 0012).
    $appsBlockedReason = $null
    if ($appDrift.Count -gt 0 -and -not $DryRun -and -not $SkipPreflight) {
        $preflight = Get-PhoenixPreflightState
        if (-not $preflight.Safe) {
            $appsBlockedReason = (($preflight.Results | Where-Object Status -eq 'FAIL' | ForEach-Object { $_.Name }) -join ', ')
            Write-PhoenixLog -Level WARNING -Message "[StateEngine] Preflight not safe ($appsBlockedReason) - application repairs skipped. Setting repairs continue."
        }
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $settingDrift) {
        if ($DryRun) {
            $results.Add([PSCustomObject]@{ Category = 'Setting'; Name = $item.Name; Status = 'WARN'; Message = 'DRY RUN - would re-apply this setting.'; Changed = $false })
            continue
        }
        $results.Add((Set-PhoenixSetting -Manifest $item.Manifest))
    }

    foreach ($item in $appDrift) {
        $verb = if ($item.DriftType -eq 'Outdated') { 'upgrade' } else { 'install' }

        if ($DryRun) {
            $results.Add([PSCustomObject]@{ Category = 'Application'; Name = $item.Name; Status = 'WARN'; Message = "DRY RUN - would $verb this application."; Changed = $false })
            continue
        }
        if ($appsBlockedReason) {
            $results.Add([PSCustomObject]@{ Category = 'Application'; Name = $item.Name; Status = 'WARN'; Message = "Skipped - system not in a safe state for installation ($appsBlockedReason)."; Changed = $false })
            continue
        }

        if ($item.DriftType -eq 'Outdated') {
            $results.Add((Update-PhoenixApplication -Manifest $item.Manifest))
        }
        else {
            $results.Add((Install-PhoenixApplication -Manifest $item.Manifest))
        }
    }

    $resultArray = $results.ToArray()
    $failed = @($resultArray | Where-Object Status -eq 'FAIL')

    if ($Transactional -and $failed.Count -gt 0) {
        Write-PhoenixLog -Level ERROR -Message "[StateEngine] Repair failed for $($failed.Count) item(s) - reversing the repairs that changed..."
        # Wrap the repair results in the health-result shape the rollback
        # engine consumes; only Changed = $true entries are reversed.
        $null = Invoke-PhoenixRollbackFromResults -Results @([PSCustomObject]@{ Module = 'StateEngine'; Details = $resultArray }) -RootPath $RootPath
    }
    elseif ($failed.Count -gt 0) {
        Write-PhoenixLog -Level WARNING -Message "[StateEngine] Repair completed with $($failed.Count) failure(s) out of $($resultArray.Count) item(s)."
    }
    else {
        Write-PhoenixLog -Level SUCCESS -Message "[StateEngine] Repair complete: $($resultArray.Count) item(s) processed."
    }

    return $resultArray
}

Export-ModuleMember -Function Get-PhoenixState, Compare-PhoenixState, Invoke-PhoenixAudit, Invoke-PhoenixRepair
