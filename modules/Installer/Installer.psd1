@{
    RootModule        = 'Installer.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7d2a8ba-cf40-4b9c-ad80-7f8b9c0d1e2f'
    Author            = 'Project Phoenix'
    Description       = 'Application Deployment Engine (Roadmap 0.6 / ADR 0007): manifest-driven installer with WinGet/MSI/EXE backends. Requires PhoenixLogging to be imported first; imports Validation, PhoenixConfig, and PhoenixBootstrap itself.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixApplicationManifest', 'Get-PhoenixConfigValue', 'Test-PhoenixApplicationSatisfied', 'Install-PhoenixWinGetPackage', 'Install-PhoenixMsiPackage', 'Install-PhoenixExePackage', 'Install-PhoenixApplication', 'Install-PhoenixApplications', 'Get-PhoenixProfile', 'Expand-PhoenixProfileApplications', 'Invoke-PhoenixProfile', 'Get-InstallerModuleDefinition')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
