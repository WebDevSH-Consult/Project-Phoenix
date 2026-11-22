@{
    RootModule        = 'PlanFreshness.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '9c3e7b1d-5a2f-4e8b-b6d4-0c5f1a7e005b'
    Author            = 'Project Phoenix'
    Description       = 'PHX-005B plan provenance (machine identity and configuration, manifest and state fingerprints) and the read-only freshness gate that rejects stale approved plans. Does not execute deployments.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-PhoenixMachineIdentity',
        'Get-PhoenixConfigurationFingerprint',
        'Get-PhoenixManifestFingerprint',
        'Get-PhoenixStateFingerprint',
        'New-PhoenixContractPlan',
        'Test-PhoenixPlanFreshness',
        'Assert-PhoenixPlanFreshness'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
