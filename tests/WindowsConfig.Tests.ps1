Describe 'Get-PhoenixSettingManifest' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/WindowsConfig/WindowsConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FixtureSettingsPath {
            param([hashtable]$Files)

            $path = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            foreach ($entry in $Files.GetEnumerator()) {
                Set-Content -Path (Join-Path $path $entry.Key) -Value $entry.Value
            }
            return $path
        }
    }

    It 'discovers and parses a valid Registry setting manifest' {
        $json = '{"Name":"Sample","Type":"Registry","ConfigFlag":"windows.Sample","Path":"HKCU:\\Software\\Test","ValueName":"V","DesiredValue":1,"ValueKind":"DWord"}'
        $path = New-FixtureSettingsPath -Files @{ 'sample.json' = $json }

        $manifests = Get-PhoenixSettingManifest -ManifestsPath $path

        $manifests.Count | Should -Be 1
        $manifests[0].Name | Should -Be 'Sample'
        $manifests[0].ValueName | Should -Be 'V'
    }

    It 'throws when a required base field is missing' {
        $path = New-FixtureSettingsPath -Files @{ 'incomplete.json' = '{"Name":"Incomplete"}' }

        { Get-PhoenixSettingManifest -ManifestsPath $path } | Should -Throw '*Incomplete*'
    }

    It 'throws on an unknown Type' {
        $json = '{"Name":"Bad","Type":"Telepathy","ConfigFlag":"windows.Bad"}'
        $path = New-FixtureSettingsPath -Files @{ 'bad.json' = $json }

        { Get-PhoenixSettingManifest -ManifestsPath $path } | Should -Throw '*Telepathy*'
    }

    It 'throws when a Registry manifest is missing a registry-specific field' {
        $json = '{"Name":"NoPath","Type":"Registry","ConfigFlag":"windows.NoPath","ValueName":"V","DesiredValue":1,"ValueKind":"DWord"}'
        $path = New-FixtureSettingsPath -Files @{ 'nopath.json' = $json }

        { Get-PhoenixSettingManifest -ManifestsPath $path } | Should -Throw "*'Path'*"
    }

    It 'throws on malformed JSON' {
        $path = New-FixtureSettingsPath -Files @{ 'broken.json' = '{ not valid json' }

        { Get-PhoenixSettingManifest -ManifestsPath $path } | Should -Throw '*broken.json*'
    }

    It 'throws on duplicate setting names' {
        $json = '{"Name":"Dup","Type":"Registry","ConfigFlag":"windows.Dup","Path":"HKCU:\\Software\\Test","ValueName":"V","DesiredValue":1,"ValueKind":"DWord"}'
        $path = New-FixtureSettingsPath -Files @{ 'a.json' = $json; 'b.json' = $json }

        { Get-PhoenixSettingManifest -ManifestsPath $path } | Should -Throw '*Dup*'
    }

    It 'discovers the real shipped manifests, and every ConfigFlag resolves to a declared config property' {
        Import-Module "$PSScriptRoot/../modules/PhoenixConfig/PhoenixConfig.psd1" -Force
        $manifests = Get-PhoenixSettingManifest -ManifestsPath (Resolve-Path "$PSScriptRoot/../modules/WindowsConfig/Settings")
        $config = Get-PhoenixConfiguration -RootPath (Resolve-Path "$PSScriptRoot/..")

        $manifests.Count | Should -BeGreaterOrEqual 4
        foreach ($manifest in $manifests) {
            $domain, $property = $manifest.ConfigFlag -split '\.', 2
            $config.Modules.PSObject.Properties.Name | Should -Contain $domain
            $config.Modules.$domain.PSObject.Properties.Name | Should -Contain $property
        }
    }
}

Describe 'Test-PhoenixSettingApplied / Set-PhoenixSetting' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/WindowsConfig/WindowsConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        $script:SampleManifest = [PSCustomObject]@{
            Name         = 'Sample'
            Type         = 'Registry'
            ConfigFlag   = 'windows.Sample'
            Path         = 'HKCU:\Software\PhoenixTest'
            ValueName    = 'V'
            DesiredValue = 1
            ValueKind    = 'DWord'
        }
    }

    It 'Test-PhoenixSettingApplied is true when the current value matches' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 1 }
        Test-PhoenixSettingApplied -Manifest $script:SampleManifest | Should -Be $true
    }

    It 'Test-PhoenixSettingApplied is false when the current value differs' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 0 }
        Test-PhoenixSettingApplied -Manifest $script:SampleManifest | Should -Be $false
    }

    It 'Test-PhoenixSettingApplied is false when the value is unset' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { $null }
        Test-PhoenixSettingApplied -Manifest $script:SampleManifest | Should -Be $false
    }

    It 'skips writing and reports PASS when already in the desired state' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 1 }
        Mock -ModuleName WindowsConfig Set-PhoenixRegistryValue { throw 'should not be called' }

        $result = Set-PhoenixSetting -Manifest $script:SampleManifest

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'Already in desired state'
    }

    It 'applies, records the previous value, and reports PASS when the write verifies' {
        $script:RegistryState = 0
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { $script:RegistryState }
        Mock -ModuleName WindowsConfig Set-PhoenixRegistryValue { $script:RegistryState = 1 }

        $result = Set-PhoenixSetting -Manifest $script:SampleManifest

        $result.Status | Should -Be 'PASS'
        $result.PreviousValue | Should -Be 0
        Should -Invoke -ModuleName WindowsConfig Set-PhoenixRegistryValue -Times 1
    }

    It 'reports FAIL when the write does not stick' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 0 }
        Mock -ModuleName WindowsConfig Set-PhoenixRegistryValue { }

        $result = Set-PhoenixSetting -Manifest $script:SampleManifest

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match 'verification'
    }

    It 'reports FAIL, not a raw exception, when the write throws' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 0 }
        Mock -ModuleName WindowsConfig Set-PhoenixRegistryValue { throw 'access denied' }

        $result = Set-PhoenixSetting -Manifest $script:SampleManifest

        $result.Status | Should -Be 'FAIL'
        $result.Message | Should -Match 'access denied'
    }
}

Describe 'Set-PhoenixSettings' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixConfig/PhoenixConfig.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/WindowsConfig/WindowsConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'only applies settings enabled by configuration' {
        $manifests = @(
            [PSCustomObject]@{ Name = 'Enabled'; Type = 'Registry'; ConfigFlag = 'windows.A'; Path = 'HKCU:\Software\T'; ValueName = 'V'; DesiredValue = 1; ValueKind = 'DWord' }
            [PSCustomObject]@{ Name = 'Disabled'; Type = 'Registry'; ConfigFlag = 'windows.B'; Path = 'HKCU:\Software\T'; ValueName = 'W'; DesiredValue = 1; ValueKind = 'DWord' }
        )
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ windows = [PSCustomObject]@{ A = $true; B = $false } } }

        Mock -ModuleName WindowsConfig Set-PhoenixSetting {
            param($Manifest)
            [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'PASS'; Message = 'mocked'; PreviousValue = $null }
        }

        $results = Set-PhoenixSettings -Manifests $manifests -Configuration $config

        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'Enabled'
    }
}

Describe 'Get-WindowsConfigModuleDefinition' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixCore/PhoenixCore.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/WindowsConfig/WindowsConfig.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'returns a definition with the WindowsConfig name and all four lifecycle stages' {
        $definition = Get-WindowsConfigModuleDefinition

        $definition.Name | Should -Be 'WindowsConfig'
        $definition.Initialize | Should -Not -BeNullOrEmpty
        $definition.Validate | Should -Not -BeNullOrEmpty
        $definition.Execute | Should -Not -BeNullOrEmpty
        $definition.Verify | Should -Not -BeNullOrEmpty
    }

    It 'runs the full lifecycle with mocked registry access and reports Healthy' {
        Mock -ModuleName WindowsConfig Get-PhoenixRegistryValue { 99 }
        Mock -ModuleName WindowsConfig Set-PhoenixRegistryValue { }
        Mock -ModuleName WindowsConfig Test-PhoenixSettingApplied { $true }

        $definition = Get-WindowsConfigModuleDefinition
        $health = Invoke-PhoenixModuleLifecycle @definition

        $health.Status | Should -Be 'Healthy'
    }
}
