BeforeAll {
    Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
    Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
    Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
}

Describe 'Invoke-PhoenixModuleLifecycle' {
    It 'reports Healthy when all stages succeed' {
        $health = Invoke-PhoenixModuleLifecycle -Name 'Test' -Validate { $true } -Verify { $true }
        $health.Status | Should -Be 'Healthy'
        $health.HealthPercent | Should -Be 100
    }

    It 'reports Error and captures the exception message when Execute throws' {
        $health = Invoke-PhoenixModuleLifecycle -Name 'Test' -Execute { throw 'boom' }
        $health.Status | Should -Be 'Error'
        $health.HealthPercent | Should -Be 0
        $health.Issues | Should -Contain 'boom'
    }

    It 'reports Warning when Verify returns false' {
        $health = Invoke-PhoenixModuleLifecycle -Name 'Test' -Verify { $false }
        $health.Status | Should -Be 'Warning'
        $health.HealthPercent | Should -Be 50
    }

    It 'reports Error when Validate returns false' {
        $health = Invoke-PhoenixModuleLifecycle -Name 'Test' -Validate { $false }
        $health.Status | Should -Be 'Error'
    }

    It 'defaults to Healthy when no script blocks are provided' {
        $health = Invoke-PhoenixModuleLifecycle -Name 'NoOp'
        $health.Status | Should -Be 'Healthy'
    }
}

Describe 'Invoke-PhoenixBootstrap' {
    It 'returns one health object per registered module' {
        $modules = @(
            @{ Name = 'A'; Validate = { $true }; Verify = { $true } }
            @{ Name = 'B'; Validate = { $true }; Verify = { $true } }
        )
        $results = Invoke-PhoenixBootstrap -Modules $modules
        $results.Count | Should -Be 2
        $results.Module | Should -Contain 'A'
        $results.Module | Should -Contain 'B'
    }
}

Describe 'Get-PhoenixVersion' {
    It 'parses the VERSION file into Version/Major/Minor/Patch' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -Path (Join-Path $root 'VERSION') -Value '1.2.3'

        $version = Get-PhoenixVersion -RootPath $root

        $version.Version | Should -Be '1.2.3'
        $version.Major | Should -Be 1
        $version.Minor | Should -Be 2
        $version.Patch | Should -Be 3
    }

    It 'throws a clean error when VERSION is missing' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        { Get-PhoenixVersion -RootPath $root } | Should -Throw '*VERSION*'
    }
}
