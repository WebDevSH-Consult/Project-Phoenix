@{
    RootModule        = 'PlanContracts.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '4f24a6b8-1a62-4d91-8f17-8a5f2a9c005a'
    Author            = 'Project Phoenix'
    Description       = 'PHX-005A versioned deployment-plan and explicit operator-approval contracts with canonical SHA-256 integrity validation. Does not execute deployments.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'ConvertTo-PhoenixCanonicalJson',
        'Get-PhoenixDeploymentPlanDigest',
        'New-PhoenixDeploymentPlanContract',
        'Assert-PhoenixDeploymentPlanContract',
        'Test-PhoenixDeploymentPlanContract',
        'New-PhoenixApprovalRecord',
        'Assert-PhoenixApprovalRecord',
        'Test-PhoenixApprovalRecord',
        'ConvertFrom-PhoenixContractJson',
        'Read-PhoenixDeploymentPlanContract',
        'Read-PhoenixApprovalRecord'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
