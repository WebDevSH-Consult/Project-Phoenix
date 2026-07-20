#Requires -Version 7.0
<#
    .SYNOPSIS
    Project Phoenix entry point.

    .DESCRIPTION
    Loads configuration, then hands off to the Bootstrap Engine (PhoenixBootstrap),
    which discovers every module under modules/ with a module.json manifest, resolves
    their dependency order, and runs each one through Phoenix Core's lifecycle
    dispatcher (Initialise -> Validate -> Execute -> Verify -> Log -> Report).
    Bootstrap.ps1 itself knows nothing about any specific module - see
    modules/PhoenixBootstrap/README.md and ARCHITECTURE.md for the full design.
#>
[CmdletBinding()]
param(
    [switch]$Version,
    [switch]$Plan,

    # All-or-nothing run (ADR 0017): if any module does not end Healthy, Phoenix
    # automatically reverses every confirmed change this run made. Opt-in; the
    # default run leaves earlier successful changes in place.
    [switch]$Transactional
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot

if ($Version) {
    Import-Module (Join-Path $root 'modules/PhoenixLogging/PhoenixLogging.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixCore/PhoenixCore.psd1') -Force
    Write-Output "Project Phoenix v$((Get-PhoenixVersion -RootPath $root).Version)"
    return
}

if ($Plan) {
    # Review before deploy (ADR 0016): build a configuration-scoped deployment
    # plan, show it, export it, and exit WITHOUT executing anything.
    Import-Module (Join-Path $root 'modules/PhoenixLogging/PhoenixLogging.psd1') -Force
    Import-Module (Join-Path $root 'modules/DeploymentPlanner/DeploymentPlanner.psd1') -Force
    Initialize-PhoenixLog -LogDirectory (Join-Path $root 'logs')

    $deploymentPlan = New-PhoenixDeploymentPlan -RootPath $root
    Show-PhoenixDeploymentPlan -Plan $deploymentPlan
    $null = Export-PhoenixDeploymentPlan -Plan $deploymentPlan -RootPath $root
    return
}

$transcriptPath = Join-Path $root "logs/transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
Start-Transcript -Path $transcriptPath -Force | Out-Null

try {
    Import-Module (Join-Path $root 'modules/PhoenixLogging/PhoenixLogging.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixCore/PhoenixCore.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixConfig/PhoenixConfig.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixBootstrap/PhoenixBootstrap.psd1') -Force
    Import-Module (Join-Path $root 'modules/Dashboard/Dashboard.psd1') -Force
    if ($Transactional) {
        Import-Module (Join-Path $root 'modules/Recovery/Recovery.psd1') -Force
    }

    Initialize-PhoenixLog -LogDirectory (Join-Path $root 'logs')

    $config = Get-PhoenixConfiguration -RootPath $root
    $phoenixVersion = Get-PhoenixVersion -RootPath $root
    Write-PhoenixLog -Level INFO -Message "Project Phoenix v$($phoenixVersion.Version) starting... (config version: $($config.version))"
    if ($Transactional) {
        Write-PhoenixLog -Level INFO -Message 'Transactional run: all-or-nothing. If any module does not end Healthy, this run''s confirmed changes will be reversed automatically.'
    }

    if (Test-PhoenixElevated) {
        Write-PhoenixLog -Level INFO -Message 'Running elevated: machine-scope settings will be applied.'
    }
    else {
        Write-PhoenixLog -Level WARNING -Message 'Running without elevation: machine-scope settings (RequiresElevation) will be skipped with a WARN. Re-run from an elevated PowerShell to apply them.'
    }

    $started = Get-Date
    $results = Invoke-PhoenixOrchestration -RootPath $root
    $duration = ((Get-Date) - $started).TotalSeconds

    $null = New-PhoenixDeploymentReport -ModuleHealth $results -RootPath $root -DurationSeconds $duration

    if ($Transactional) {
        $unhealthy = @($results | Where-Object Status -ne 'Healthy')
        if ($unhealthy.Count -gt 0) {
            $names = ($unhealthy | ForEach-Object { "$($_.Module) ($($_.Status))" }) -join ', '
            Write-PhoenixLog -Level ERROR -Message "Transaction failed: $($unhealthy.Count) module(s) did not end Healthy [$names]. Rolling back this run's confirmed changes..."
            $rollback = Invoke-PhoenixRollbackFromResults -Results $results -RootPath $root
            $rollbackFailures = @($rollback | Where-Object Status -eq 'FAIL')
            if ($rollbackFailures.Count -gt 0) {
                Write-PhoenixLog -Level ERROR -Message "Transaction rolled back with $($rollbackFailures.Count) reversal failure(s): the machine may be left partially changed. Review the log and the deployment report."
            }
            else {
                Write-PhoenixLog -Level WARNING -Message "Transaction rolled back: $($rollback.Count) change(s) reversed. The run did not complete; no net change was committed."
            }
        }
        else {
            Write-PhoenixLog -Level SUCCESS -Message 'Transaction committed: every module ended Healthy.'
        }
    }

    Write-PhoenixLog -Level SUCCESS -Message 'Bootstrap complete.'
}
finally {
    Stop-Transcript | Out-Null
}
