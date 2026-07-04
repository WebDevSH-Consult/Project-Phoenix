@{
    RootModule        = 'HardwareDetection.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'ea05dbed-f173-4cef-b013-acbe2f3a4b5c'
    Author            = 'Project Phoenix'
    Description       = 'Hardware Detection Engine (ADR 0011): one authoritative Get-PhoenixHardware object - CPU, GPUs, memory, form factor, VM detection, TPM, Secure Boot, disks, network. Detected, never assumed. Requires PhoenixLogging to be imported first for the orchestrated lifecycle.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-PhoenixCimInstance', 'Get-PhoenixTpmState', 'Get-PhoenixSecureBootState', 'Get-PhoenixGpuInfo', 'Get-PhoenixHardware', 'Get-HardwareDetectionModuleDefinition')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
