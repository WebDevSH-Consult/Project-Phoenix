@{
    RootModule        = 'Dashboard.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'd9f4cadc-e062-4bde-af02-9bad1e2f3a4b'
    Author            = 'Project Phoenix'
    Description       = 'Health Dashboard (Roadmap 0.9 / ADR 0010): generates HTML + JSON deployment reports after every Bootstrap run. Engine module called by Bootstrap.ps1, not orchestrated. Requires PhoenixLogging to be imported first; imports PhoenixCore and Validation itself.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixGitCommit', 'ConvertTo-PhoenixHtmlReport', 'New-PhoenixDeploymentReport')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
