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

    Slice 1 (this file): Get-PhoenixState, Compare-PhoenixState,
    Invoke-PhoenixAudit - all read-only. Invoke-PhoenixRepair follows in
    slice 2.

    Operator-invoked (the maintain path), not an orchestrated forward stage -
    no module.json. Depends on PhoenixLogging; imports the capability modules
    it consumes itself.
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\WindowsConfig\WindowsConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Installer\Installer.psd1')

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

Export-ModuleMember -Function Get-PhoenixState, Compare-PhoenixState, Invoke-PhoenixAudit
