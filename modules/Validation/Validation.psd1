@{
    RootModule        = 'Validation.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a6c1f7a9-be3f-4a8b-9c7d-6e7f8a9b0c1d'
    Author            = 'Project Phoenix'
    Description       = 'System validation engine (EPIC-04): hardware-agnostic PASS/WARN/FAIL checks. Requires PhoenixLogging to be imported first.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixGpuInfo', 'Test-PhoenixGpu', 'Test-PhoenixCommandAvailable', 'Test-PhoenixAppxPackageAvailable', 'Test-PhoenixPathExists', 'Test-PhoenixWinGetPackageInstalled', 'Invoke-PhoenixValidationReport', 'Get-ValidationModuleDefinition')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
