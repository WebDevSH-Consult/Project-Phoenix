Describe 'Get-PhoenixConfiguration' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixConfig/PhoenixConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FixtureRoot {
            param([hashtable]$RootContent, [hashtable]$DomainFiles = @{})

            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'configs') -Force | Out-Null

            $RootContent | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $fixtureRoot 'phoenix.json')

            foreach ($entry in $DomainFiles.GetEnumerator()) {
                $path = Join-Path $fixtureRoot $entry.Key
                Set-Content -Path $path -Value $entry.Value
            }

            return $fixtureRoot
        }
    }

    It 'returns a merged object with root fields and every domain config attached' {
        $root = New-FixtureRoot -RootContent @{
            version = '9.9.9'
            name    = 'Test Phoenix'
            modules = @{ windows = 'configs/windows.json' }
        } -DomainFiles @{
            'configs/windows.json' = '{"DarkMode": true}'
        }

        $config = Get-PhoenixConfiguration -RootPath $root

        $config.version | Should -Be '9.9.9'
        $config.name | Should -Be 'Test Phoenix'
        $config.Modules.windows.DarkMode | Should -Be $true
    }

    It 'loads multiple domain files correctly' {
        $root = New-FixtureRoot -RootContent @{
            version = '1.0.0'
            modules = @{
                windows = 'configs/windows.json'
                gaming  = 'configs/gaming.json'
            }
        } -DomainFiles @{
            'configs/windows.json' = '{"DarkMode": true}'
            'configs/gaming.json'  = '{"InstallSteam": true}'
        }

        $config = Get-PhoenixConfiguration -RootPath $root

        $config.Modules.windows.DarkMode | Should -Be $true
        $config.Modules.gaming.InstallSteam | Should -Be $true
    }

    It 'throws a clean error when phoenix.json is missing' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        { Get-PhoenixConfiguration -RootPath $root } | Should -Throw '*phoenix.json*'
    }

    It 'throws a clean error when a referenced domain file is missing' {
        $root = New-FixtureRoot -RootContent @{
            version = '1.0.0'
            modules = @{ windows = 'configs/windows.json' }
        }

        { Get-PhoenixConfiguration -RootPath $root } | Should -Throw '*windows*'
    }

    It 'throws a clean error when phoenix.json contains malformed JSON' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -Path (Join-Path $root 'phoenix.json') -Value '{ not valid json'

        { Get-PhoenixConfiguration -RootPath $root } | Should -Throw '*phoenix.json*'
    }

    It 'throws a clean error when a referenced domain file contains malformed JSON' {
        $root = New-FixtureRoot -RootContent @{
            version = '1.0.0'
            modules = @{ windows = 'configs/windows.json' }
        } -DomainFiles @{
            'configs/windows.json' = '{ not valid json'
        }

        { Get-PhoenixConfiguration -RootPath $root } | Should -Throw '*windows*'
    }
}

Describe 'Get-PhoenixConfigValue' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixConfig/PhoenixConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'resolves a true dot-path' {
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ applications = [PSCustomObject]@{ InstallGit = $true } } }

        Get-PhoenixConfigValue -Configuration $config -Path 'applications.InstallGit' | Should -Be $true
    }

    It 'resolves a false dot-path' {
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ applications = [PSCustomObject]@{ InstallGit = $false } } }

        Get-PhoenixConfigValue -Configuration $config -Path 'applications.InstallGit' | Should -Be $false
    }

    It 'returns false, never throws, when the path segment does not exist' {
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ applications = [PSCustomObject]@{} } }

        Get-PhoenixConfigValue -Configuration $config -Path 'applications.InstallSomethingUndeclared' | Should -Be $false
    }

    It 'returns false when the whole domain is missing' {
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{} }

        Get-PhoenixConfigValue -Configuration $config -Path 'gaming.InstallSteam' | Should -Be $false
    }
}
