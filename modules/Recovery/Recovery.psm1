<#
    Phoenix Recovery / Rollback Engine (ADR 0015).

    Reverses the changes a deployment made, driven by the deployment report
    the run already produced (ADR 0010) joined with the manifests that
    describe how to reverse each change. Reverses confirmed changes only
    (Changed = $true): settings return to their previous value (or are
    removed if Phoenix introduced them), applications Phoenix installed are
    uninstalled - each verified.

    Operator-invoked (Invoke-PhoenixRollback), not an orchestrated stage -
    rollback is a recovery action, not forward deployment. No module.json.

    Depends on PhoenixLogging being imported first; imports WindowsConfig
    (registry provider + setting manifests) and Installer (uninstall + app
    manifests) itself.
#>

Import-Module (Join-Path $PSScriptRoot '..\WindowsConfig\WindowsConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Installer\Installer.psd1')

#region Reversal primitives

function Undo-PhoenixSettingChange {
    <#
        .SYNOPSIS
        Restores a single setting to its previous value, or removes it if
        Phoenix introduced it (previous value was unset). Verifies the
        restore took effect.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ValueName,

        [string]$ValueKind = 'DWord',

        # The value before Phoenix changed it. $null means it was unset -
        # rollback removes the value entirely.
        $PreviousValue
    )

    try {
        if ($null -eq $PreviousValue) {
            Remove-PhoenixRegistryValue -Path $Path -ValueName $ValueName
            $restored = ($null -eq (Get-PhoenixRegistryValue -Path $Path -ValueName $ValueName))
            $target = '(removed - value was previously unset)'
        }
        else {
            Set-PhoenixRegistryValue -Path $Path -ValueName $ValueName -Value $PreviousValue -ValueKind $ValueKind
            $current = Get-PhoenixRegistryValue -Path $Path -ValueName $ValueName
            $restored = ("$current" -eq "$PreviousValue")
            $target = "restored to '$PreviousValue'"
        }
    }
    catch {
        Write-PhoenixLog -Level ERROR -Message "[Recovery] $Name`: rollback failed - $($_.Exception.Message)"
        return [PSCustomObject]@{ Category = 'Rollback'; Name = $Name; Status = 'FAIL'; Message = "Rollback failed: $($_.Exception.Message)" }
    }

    if ($restored) {
        Write-PhoenixLog -Level SUCCESS -Message "[Recovery] $Name`: rolled back ($target)."
        return [PSCustomObject]@{ Category = 'Rollback'; Name = $Name; Status = 'PASS'; Message = "Setting rolled back: $target." }
    }

    Write-PhoenixLog -Level ERROR -Message "[Recovery] $Name`: rollback did not restore the previous value."
    return [PSCustomObject]@{ Category = 'Rollback'; Name = $Name; Status = 'FAIL'; Message = 'Rollback did not restore the previous value.' }
}

function Undo-PhoenixApplicationInstall {
    <#
        .SYNOPSIS
        Reverses an installation by uninstalling the application, reusing the
        Installer's Uninstall-PhoenixApplication (which verifies removal).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $result = Uninstall-PhoenixApplication -Manifest $Manifest
    return [PSCustomObject]@{ Category = 'Rollback'; Name = $Manifest.Name; Status = $result.Status; Message = "Install rollback: $($result.Message)" }
}

#endregion

#region Plan + orchestration

function Get-PhoenixRollbackPlan {
    <#
        .SYNOPSIS
        Builds an ordered rollback plan from a deployment report, joining each
        confirmed change (Changed = $true) to the manifest that describes how
        to reverse it.

        .DESCRIPTION
        Returns plan entries in reverse-of-application order (applications
        first, since they install after settings), each carrying everything
        Undo-* needs. A changed detail with no matching manifest is skipped
        with a WARNING rather than failing the whole plan.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$SettingManifests,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$ApplicationManifests
    )

    $settingByName = @{}
    foreach ($m in $SettingManifests) { $settingByName[$m.Name] = $m }
    $appByName = @{}
    foreach ($m in $ApplicationManifests) { $appByName[$m.Name] = $m }

    $settingEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $appEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($module in @($Report.Modules)) {
        foreach ($detail in @($module.Details)) {
            $changed = ($detail.PSObject.Properties.Name -contains 'Changed' -and $detail.Changed)
            if (-not $changed) { continue }

            switch ($detail.Category) {
                'Setting' {
                    if (-not $settingByName.ContainsKey($detail.Name)) {
                        Write-PhoenixLog -Level WARNING -Message "[Recovery] Changed setting '$($detail.Name)' in the report has no matching manifest - skipping."
                        continue
                    }
                    $manifest = $settingByName[$detail.Name]
                    $previous = if ($detail.PSObject.Properties.Name -contains 'PreviousValue') { $detail.PreviousValue } else { $null }
                    $settingEntries.Add([PSCustomObject]@{
                        Type          = 'Setting'
                        Name          = $detail.Name
                        Path          = $manifest.Path
                        ValueName     = $manifest.ValueName
                        ValueKind     = $manifest.ValueKind
                        PreviousValue = $previous
                    })
                }
                'Application' {
                    if (-not $appByName.ContainsKey($detail.Name)) {
                        Write-PhoenixLog -Level WARNING -Message "[Recovery] Changed application '$($detail.Name)' in the report has no matching manifest - skipping."
                        continue
                    }
                    $appEntries.Add([PSCustomObject]@{
                        Type     = 'Application'
                        Name     = $detail.Name
                        Manifest = $appByName[$detail.Name]
                    })
                }
            }
        }
    }

    # Reverse-of-application order: applications (installed last) undo first,
    # then settings (changed earlier). Within each, reverse discovery order.
    $plan = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = $appEntries.Count - 1; $i -ge 0; $i--) { $plan.Add($appEntries[$i]) }
    for ($i = $settingEntries.Count - 1; $i -ge 0; $i--) { $plan.Add($settingEntries[$i]) }

    return $plan.ToArray()
}

function Invoke-PhoenixRollback {
    <#
        .SYNOPSIS
        Rolls back a deployment: restores changed settings and uninstalls
        applications Phoenix installed, in reverse order, each verified.

        .DESCRIPTION
        Reads a deployment report (the most recent under reports/ if
        -ReportPath is not given), builds a rollback plan from its confirmed
        changes, and executes it. Operator-invoked - not part of a forward
        run. See ADR 0015.

        .EXAMPLE
        Invoke-PhoenixRollback -RootPath (Get-Location)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ReportPath
    )

    if (-not $ReportPath) {
        $reportsDir = Join-Path $RootPath 'reports'
        $latest = Get-ChildItem -LiteralPath $reportsDir -Filter 'deployment-report-*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if (-not $latest) {
            Write-PhoenixLog -Level ERROR -Message "[Recovery] No deployment report found under $reportsDir - nothing to roll back."
            throw "No deployment report found under $reportsDir."
        }
        $ReportPath = $latest.FullName
    }

    Write-PhoenixLog -Level INFO -Message "[Recovery] Rolling back from report: $ReportPath"
    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json

    $settingManifests = @(Get-PhoenixSettingManifest -ManifestsPath (Join-Path $RootPath 'modules\WindowsConfig\Settings'))
    $appManifests = @(Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $RootPath 'modules\Installer\Applications'))

    $plan = Get-PhoenixRollbackPlan -Report $report -SettingManifests $settingManifests -ApplicationManifests $appManifests
    Write-PhoenixLog -Level INFO -Message "[Recovery] Rollback plan: $($plan.Count) change(s) to reverse."

    $results = @(
        foreach ($entry in $plan) {
            switch ($entry.Type) {
                'Application' { Undo-PhoenixApplicationInstall -Manifest $entry.Manifest }
                'Setting' { Undo-PhoenixSettingChange -Name $entry.Name -Path $entry.Path -ValueName $entry.ValueName -ValueKind $entry.ValueKind -PreviousValue $entry.PreviousValue }
            }
        }
    )

    $failed = @($results | Where-Object Status -eq 'FAIL')
    if ($failed.Count -gt 0) {
        Write-PhoenixLog -Level WARNING -Message "[Recovery] Rollback completed with $($failed.Count) failure(s) out of $($results.Count) change(s)."
    }
    else {
        Write-PhoenixLog -Level SUCCESS -Message "[Recovery] Rollback complete: $($results.Count) change(s) reversed."
    }

    return $results
}

#endregion

Export-ModuleMember -Function Undo-PhoenixSettingChange, Undo-PhoenixApplicationInstall, Get-PhoenixRollbackPlan, Invoke-PhoenixRollback
