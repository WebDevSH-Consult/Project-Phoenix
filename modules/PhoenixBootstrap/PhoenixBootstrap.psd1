@{
    RootModule        = 'PhoenixBootstrap.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'f5dae6f8-ad2e-4f7a-be6f-5a6b7c8d9e0f'
    Author            = 'Project Phoenix'
    Description       = 'Bootstrap orchestration engine: discovers module.json manifests, resolves dependency order, and executes modules through PhoenixCore. Requires PhoenixLogging and PhoenixCore to be imported first.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixModuleManifest', 'Resolve-PhoenixModuleOrder', 'Invoke-PhoenixOrchestration')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
