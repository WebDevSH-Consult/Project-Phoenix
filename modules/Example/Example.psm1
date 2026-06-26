<#
    Example module - demonstrates the Phoenix module contract described in
    modules/PhoenixCore/README.md. Copy this as a starting point for a new module;
    replace the script blocks with real Initialise/Validate/Execute/Verify logic.
#>

function Get-ExampleModuleDefinition {
    <#
        .SYNOPSIS
        Returns the module definition hashtable consumed by Invoke-PhoenixModuleLifecycle.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name       = 'Example'
        Initialize = { Write-PhoenixLog -Level INFO -Message '[Example] Nothing to initialise.' }
        Validate   = { $true }
        Execute    = { Write-PhoenixLog -Level INFO -Message '[Example] Pretending to do work.' }
        Verify     = { $true }
    }
}

Export-ModuleMember -Function Get-ExampleModuleDefinition
