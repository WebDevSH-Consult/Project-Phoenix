@{
    RootModule        = 'StateEngine.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b8d41e6a-2f57-4c93-a1d8-3e0f7c9b2a41'
    Author            = 'Project Phoenix'
    Description       = 'Desired State & Drift Management Engine (ADR 0018, PHX-004): the single source of truth for current-vs-desired state. Get-PhoenixState builds the current-state model, Compare-PhoenixState returns the drift set, Invoke-PhoenixAudit reports drift (read-only), and Invoke-PhoenixRepair re-applies desired state for only the drifted items via the existing idempotent apply/install/upgrade functions. Orchestrates the existing predicates and mutators; reimplements no check or mutation. Operator-invoked, not orchestrated. Requires PhoenixLogging to be imported first; imports PhoenixConfig, Validation, WindowsConfig, Installer, and Recovery.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixState', 'Compare-PhoenixState', 'Invoke-PhoenixAudit', 'Invoke-PhoenixRepair')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
