@{
    RootModule        = 'Recovery.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'fb16ecfe-0284-4df0-c124-bdcf3a4b5c6d'
    Author            = 'Project Phoenix'
    Description       = 'Recovery / Rollback Engine (ADR 0015): reverses a deployment (restore settings to their previous value, uninstall installed applications) driven by the deployment report + manifests. Operator-invoked, not orchestrated. Requires PhoenixLogging to be imported first; imports WindowsConfig and Installer itself.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Undo-PhoenixSettingChange', 'Undo-PhoenixApplicationInstall', 'Get-PhoenixRollbackPlan', 'Invoke-PhoenixRollback')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
