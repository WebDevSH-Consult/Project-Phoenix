@{
    RootModule        = 'DeploymentPlanner.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'ac27fd0f-1395-4e01-b235-cea04b5c6d7e'
    Author            = 'Project Phoenix'
    Description       = 'Intelligent Deployment Planner (ADR 0016): builds an explainable, exportable deployment plan (Install/Apply/Skip/Defer, with reasons) without executing. Current-vs-desired state and scoping come from the State Engine (ADR 0018); the planner adds the deploy-time decisions - deferral, ordering, estimates, risk. Operator-invoked, not orchestrated. Requires PhoenixLogging to be imported first; imports PhoenixCore, HardwareDetection, Validation, and StateEngine.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('New-PhoenixDeploymentPlan', 'Show-PhoenixDeploymentPlan', 'Export-PhoenixDeploymentPlan', 'Get-PhoenixDeploymentPlan')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
