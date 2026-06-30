Describe 'Get-PhoenixModuleManifest' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixBootstrap/PhoenixBootstrap.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FixtureModulesRoot {
            param([hashtable[]]$Modules)

            $modulesRoot = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $modulesRoot -Force | Out-Null

            foreach ($module in $Modules) {
                $folder = Join-Path $modulesRoot $module.FolderName
                New-Item -ItemType Directory -Path $folder -Force | Out-Null

                if ($module.ContainsKey('ManifestContent')) {
                    Set-Content -Path (Join-Path $folder 'module.json') -Value $module.ManifestContent
                }

                if ($module.ContainsKey('CreatePsd1') -and $module.CreatePsd1) {
                    New-Item -ItemType File -Path (Join-Path $folder "$($module.FolderName).psd1") -Force | Out-Null
                }
            }

            return $modulesRoot
        }
    }

    It 'discovers and parses a valid module manifest' {
        $manifestJson = '{"Name":"Sample","Version":"1.0.0","Dependencies":[],"RunOrder":10,"Enabled":true,"EntryPoint":"Get-SampleModuleDefinition"}'
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'Sample'; ManifestContent = $manifestJson; CreatePsd1 = $true }
        )

        $manifests = Get-PhoenixModuleManifest -ModulesPath $root

        $manifests.Count | Should -Be 1
        $manifests[0].Name | Should -Be 'Sample'
        $manifests[0].RunOrder | Should -Be 10
        $manifests[0].Enabled | Should -Be $true
    }

    It 'ignores module folders without a module.json' {
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'NoManifest'; CreatePsd1 = $true }
        )

        $manifests = Get-PhoenixModuleManifest -ModulesPath $root

        $manifests.Count | Should -Be 0
    }

    It 'throws when module.json is malformed' {
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'Broken'; ManifestContent = '{ not valid json'; CreatePsd1 = $true }
        )

        { Get-PhoenixModuleManifest -ModulesPath $root } | Should -Throw '*Broken*'
    }

    It 'throws when a required field is missing' {
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'Incomplete'; ManifestContent = '{"Name":"Incomplete"}'; CreatePsd1 = $true }
        )

        { Get-PhoenixModuleManifest -ModulesPath $root } | Should -Throw '*Incomplete*'
    }

    It 'throws when the declared module file does not exist' {
        $manifestJson = '{"Name":"Missing","Version":"1.0.0","Dependencies":[],"RunOrder":10,"Enabled":true,"EntryPoint":"Get-MissingModuleDefinition"}'
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'Missing'; ManifestContent = $manifestJson; CreatePsd1 = $false }
        )

        { Get-PhoenixModuleManifest -ModulesPath $root } | Should -Throw '*Missing*'
    }

    It 'throws on duplicate module names' {
        $manifestJson = '{"Name":"Dup","Version":"1.0.0","Dependencies":[],"RunOrder":10,"Enabled":true,"EntryPoint":"Get-DupModuleDefinition"}'
        $root = New-FixtureModulesRoot -Modules @(
            @{ FolderName = 'DupA'; ManifestContent = $manifestJson; CreatePsd1 = $true }
            @{ FolderName = 'DupB'; ManifestContent = $manifestJson; CreatePsd1 = $true }
        )

        { Get-PhoenixModuleManifest -ModulesPath $root } | Should -Throw '*Dup*'
    }
}

Describe 'Resolve-PhoenixModuleOrder' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixBootstrap/PhoenixBootstrap.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FakeManifest {
            param([string]$Name, [string[]]$Dependencies = @(), [int]$RunOrder = 10)
            [PSCustomObject]@{ Name = $Name; Dependencies = $Dependencies; RunOrder = $RunOrder }
        }
    }

    It 'orders dependencies before dependents' {
        $a = New-FakeManifest -Name 'A'
        $b = New-FakeManifest -Name 'B' -Dependencies @('A')

        $ordered = Resolve-PhoenixModuleOrder -Manifests @($b, $a)

        $ordered[0].Name | Should -Be 'A'
        $ordered[1].Name | Should -Be 'B'
    }

    It 'breaks ties using RunOrder' {
        $a = New-FakeManifest -Name 'A' -RunOrder 20
        $b = New-FakeManifest -Name 'B' -RunOrder 10

        $ordered = Resolve-PhoenixModuleOrder -Manifests @($a, $b)

        $ordered[0].Name | Should -Be 'B'
        $ordered[1].Name | Should -Be 'A'
    }

    It 'throws when a dependency is not present' {
        $a = New-FakeManifest -Name 'A' -Dependencies @('Ghost')

        { Resolve-PhoenixModuleOrder -Manifests @($a) } | Should -Throw '*Ghost*'
    }

    It 'throws on a circular dependency' {
        $a = New-FakeManifest -Name 'A' -Dependencies @('B')
        $b = New-FakeManifest -Name 'B' -Dependencies @('A')

        { Resolve-PhoenixModuleOrder -Manifests @($a, $b) } | Should -Throw '*ircular*'
    }
}

Describe 'Invoke-PhoenixOrchestration' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixBootstrap/PhoenixBootstrap.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'runs the real Example module end-to-end and reports Healthy' {
        $repoRoot = [string](Resolve-Path "$PSScriptRoot/..")

        $results = Invoke-PhoenixOrchestration -RootPath $repoRoot

        ($results | Where-Object Module -eq 'Example').Status | Should -Be 'Healthy'
    }
}
