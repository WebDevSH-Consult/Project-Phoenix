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

$root = $PSScriptRoot

Import-Module (Join-Path $root 'modules/PhoenixLogging/PhoenixLogging.psd1') -Force
Import-Module (Join-Path $root 'modules/PhoenixCore/PhoenixCore.psd1') -Force
Import-Module (Join-Path $root 'modules/Example/Example.psd1') -Force

Initialize-PhoenixLog -LogDirectory (Join-Path $root 'logs')

$config = Get-Content (Join-Path $root 'phoenix.json') -Raw | ConvertFrom-Json
Write-PhoenixLog -Level INFO -Message "Project Phoenix v$($config.version) starting..."

$modules = @(
    Get-ExampleModuleDefinition
)

$null = Invoke-PhoenixBootstrap -Modules $modules

Write-PhoenixLog -Level SUCCESS -Message 'Bootstrap complete.'
