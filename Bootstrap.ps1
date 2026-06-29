#Requires -Version 7.0
<#
    .SYNOPSIS
    Project Phoenix entry point.

    .DESCRIPTION
    Loads configuration, then routes every registered module through Phoenix Core's
    lifecycle dispatcher (Initialise -> Validate -> Execute -> Verify -> Log -> Report).
    See ARCHITECTURE.md for the full design.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$transcriptPath = Join-Path $root "logs/transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
Start-Transcript -Path $transcriptPath -Force | Out-Null

try {
    Import-Module (Join-Path $root 'modules/PhoenixLogging/PhoenixLogging.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixCore/PhoenixCore.psd1') -Force
    Import-Module (Join-Path $root 'modules/PhoenixConfig/PhoenixConfig.psd1') -Force
    Import-Module (Join-Path $root 'modules/Example/Example.psd1') -Force

    Initialize-PhoenixLog -LogDirectory (Join-Path $root 'logs')

    $config = Get-PhoenixConfiguration -RootPath $root
    Write-PhoenixLog -Level INFO -Message "Project Phoenix v$($config.version) starting..."

    $modules = @(
        Get-ExampleModuleDefinition
    )

    $null = Invoke-PhoenixBootstrap -Modules $modules

    Write-PhoenixLog -Level SUCCESS -Message 'Bootstrap complete.'
}
finally {
    Stop-Transcript | Out-Null
}
