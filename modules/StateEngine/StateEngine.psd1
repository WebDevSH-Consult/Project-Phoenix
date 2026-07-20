@{
    RootModule        = 'StateEngine.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b8d41e6a-2f57-4c93-a1d8-3e0f7c9b2a41'
    Author            = 'Project Phoenix'
    Description       = 'Desired State & Drift Management Engine (ADR 0018, PHX-004): the single source of truth for current-vs-desired state. Get-PhoenixState builds the current-state model, Compare-PhoenixState returns the drift set, Invoke-PhoenixAudit reports drift (read-only). Orchestrates the existing predicates; reimplements no check. Operator-invoked, not orchestrated. Requires PhoenixLogging to be imported first; imports PhoenixConfig, WindowsConfig, and Installer.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixState', 'Compare-PhoenixState', 'Invoke-PhoenixAudit')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
