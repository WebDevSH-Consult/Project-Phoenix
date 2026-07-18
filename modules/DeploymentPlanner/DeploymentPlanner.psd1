@{
    RootModule        = 'DeploymentPlanner.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'ac27fd0f-1395-4e01-b235-cea04b5c6d7e'
    Author            = 'Project Phoenix'
    Description       = 'Intelligent Deployment Planner (ADR 0016): builds an explainable, exportable deployment plan (Install/Apply/Skip/Defer, with reasons) from the machine state and real capabilities, without executing. Operator-invoked, not orchestrated. Requires PhoenixLogging to be imported first; imports the capability modules it consumes.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('New-PhoenixDeploymentPlan', 'Show-PhoenixDeploymentPlan', 'Export-PhoenixDeploymentPlan', 'Get-PhoenixDeploymentPlan')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
