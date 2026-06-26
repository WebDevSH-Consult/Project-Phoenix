@{
    RootModule        = 'PhoenixCore.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c2a7f3c5-7a9b-4c4f-8b3e-2d3f4a5b6c7d'
    Author            = 'Project Phoenix'
    Description       = 'Module lifecycle dispatcher all Phoenix modules run through. Requires PhoenixLogging to be imported first.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Invoke-PhoenixModuleLifecycle', 'Invoke-PhoenixBootstrap')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
