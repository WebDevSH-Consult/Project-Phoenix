@{
    RootModule        = 'PhoenixLogging.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b1f6e2b4-6f8a-4b3e-9a2d-1c2f3a4b5c6d'
    Author            = 'Project Phoenix'
    Description       = 'Structured, leveled logging engine for Project Phoenix modules. See docs/adr/0005-logging.md.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Initialize-PhoenixLog', 'Write-PhoenixLog')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
