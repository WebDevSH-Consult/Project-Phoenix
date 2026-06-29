@{
    RootModule        = 'PhoenixConfig.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'e4c9f5e7-9c1d-4e6f-ad5f-4f5b6c7d8e9f'
    Author            = 'Project Phoenix'
    Description       = 'Configuration engine: loads phoenix.json and its referenced per-domain config files into one merged object. Requires PhoenixLogging to be imported first.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixConfiguration')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
