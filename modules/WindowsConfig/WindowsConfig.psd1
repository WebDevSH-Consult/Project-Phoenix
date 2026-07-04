@{
    RootModule        = 'WindowsConfig.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c8e3b9cb-df51-4cad-be91-8a9c0d1e2f3a'
    Author            = 'Project Phoenix'
    Description       = 'Windows Configuration Engine (Roadmap 0.8 / ADR 0009): manifest-driven Windows settings, Registry (HKCU) provider first. Requires PhoenixLogging to be imported first; imports PhoenixConfig itself.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixRegistryValue', 'Set-PhoenixRegistryValue', 'Get-PhoenixSettingManifest', 'Test-PhoenixSettingApplied', 'Set-PhoenixSetting', 'Set-PhoenixSettings', 'Get-WindowsConfigModuleDefinition')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
