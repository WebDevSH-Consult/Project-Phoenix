BeforeAll {
    Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
    Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
    Import-Module "$PSScriptRoot/../modules/Example/Example.psd1" -Force
    Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
}

Describe 'Example module' {
    It 'returns a definition with all four lifecycle stages' {
        $definition = Get-ExampleModuleDefinition
        $definition.Name | Should -Be 'Example'
        $definition.Initialize | Should -Not -BeNullOrEmpty
        $definition.Validate | Should -Not -BeNullOrEmpty
        $definition.Execute | Should -Not -BeNullOrEmpty
        $definition.Verify | Should -Not -BeNullOrEmpty
    }

    It 'runs cleanly through Invoke-PhoenixModuleLifecycle and reports Healthy' {
        $definition = Get-ExampleModuleDefinition
        $health = Invoke-PhoenixModuleLifecycle @definition
        $health.Status | Should -Be 'Healthy'
        $health.HealthPercent | Should -Be 100
    }
}
