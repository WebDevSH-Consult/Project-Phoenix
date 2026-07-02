Describe 'Get-PhoenixApplicationManifest' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FixtureManifestsPath {
            param([hashtable]$Files)

            $path = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            foreach ($entry in $Files.GetEnumerator()) {
                Set-Content -Path (Join-Path $path $entry.Key) -Value $entry.Value
            }
            return $path
        }
    }

    It 'discovers and parses a valid manifest with defaults applied' {
        $json = '{"Name":"Sample","Installer":"Winget","Id":"Sample.Id","ConfigFlag":"applications.InstallSample","Validate":[{"Type":"Command","Value":"sample"}]}'
        $path = New-FixtureManifestsPath -Files @{ 'sample.json' = $json }

        $manifests = Get-PhoenixApplicationManifest -ManifestsPath $path

        $manifests.Count | Should -Be 1
        $manifests[0].Name | Should -Be 'Sample'
        $manifests[0].RunOrder | Should -Be 100
        $manifests[0].Dependencies.Count | Should -Be 0
    }

    It 'throws when required fields are missing' {
        $path = New-FixtureManifestsPath -Files @{ 'incomplete.json' = '{"Name":"Incomplete"}' }

        { Get-PhoenixApplicationManifest -ManifestsPath $path } | Should -Throw '*Incomplete*'
    }

    It 'throws on an unknown Installer type' {
        $json = '{"Name":"Bad","Installer":"Chocolatey","ConfigFlag":"applications.InstallBad","Validate":[]}'
        $path = New-FixtureManifestsPath -Files @{ 'bad.json' = $json }

        { Get-PhoenixApplicationManifest -ManifestsPath $path } | Should -Throw '*Chocolatey*'
    }

    It 'throws on malformed JSON' {
        $path = New-FixtureManifestsPath -Files @{ 'broken.json' = '{ not valid json' }

        { Get-PhoenixApplicationManifest -ManifestsPath $path } | Should -Throw '*broken.json*'
    }

    It 'throws on duplicate application names' {
        $json = '{"Name":"Dup","Installer":"Winget","Id":"Dup.Id","ConfigFlag":"applications.InstallDup","Validate":[]}'
        $path = New-FixtureManifestsPath -Files @{ 'dupA.json' = $json; 'dupB.json' = $json }

        { Get-PhoenixApplicationManifest -ManifestsPath $path } | Should -Throw '*Dup*'
    }

    It 'discovers the real manifests shipped in modules/Installer/Applications without error' {
        $realPath = Resolve-Path "$PSScriptRoot/../modules/Installer/Applications"

        $manifests = Get-PhoenixApplicationManifest -ManifestsPath $realPath

        $manifests.Count | Should -BeGreaterOrEqual 6
        $manifests.Name | Should -Contain 'Git'
        $manifests.Name | Should -Contain 'Steam'
    }
}

Describe 'Test-PhoenixApplicationSatisfied' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'returns true when every probe passes' {
        $manifest = [PSCustomObject]@{ Name = 'Test'; Validate = @([PSCustomObject]@{ Type = 'Command'; Value = 'Get-Command' }) }

        Test-PhoenixApplicationSatisfied -Manifest $manifest | Should -Be $true
    }

    It 'returns false when a probe does not pass (FAIL)' {
        $manifest = [PSCustomObject]@{ Name = 'Test'; Validate = @([PSCustomObject]@{ Type = 'Command'; Value = 'Definitely-Not-Real-Cmd-999' }) }

        Test-PhoenixApplicationSatisfied -Manifest $manifest | Should -Be $false
    }

    It 'treats WARN as not-satisfied, even though Validation treats WARN as informational' {
        Mock -ModuleName Validation Get-AppxPackage { }

        $manifest = [PSCustomObject]@{ Name = 'Test'; Validate = @([PSCustomObject]@{ Type = 'AppxPackage'; Value = 'Some.Package' }) }

        Test-PhoenixApplicationSatisfied -Manifest $manifest | Should -Be $false
    }

    It 'throws on an unknown probe type' {
        $manifest = [PSCustomObject]@{ Name = 'Test'; Validate = @([PSCustomObject]@{ Type = 'Telepathy'; Value = 'x' }) }

        { Test-PhoenixApplicationSatisfied -Manifest $manifest } | Should -Throw '*Telepathy*'
    }
}

Describe 'Install-PhoenixWinGetPackage / Install-PhoenixMsiPackage / Install-PhoenixExePackage' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'Install-PhoenixWinGetPackage returns true on exit code 0' {
        Mock -ModuleName Installer Invoke-PhoenixWinGet { 0 }
        Install-PhoenixWinGetPackage -PackageId 'Git.Git' | Should -Be $true
    }

    It 'Install-PhoenixWinGetPackage returns false on a non-zero exit code' {
        Mock -ModuleName Installer Invoke-PhoenixWinGet { 1 }
        Install-PhoenixWinGetPackage -PackageId 'Git.Git' | Should -Be $false
    }

    It 'Install-PhoenixMsiPackage returns true on exit code 0' {
        Mock -ModuleName Installer Invoke-PhoenixMsiExec { 0 }
        Install-PhoenixMsiPackage -Path 'C:\fake.msi' | Should -Be $true
    }

    It 'Install-PhoenixMsiPackage treats exit code 3010 (reboot required) as success' {
        Mock -ModuleName Installer Invoke-PhoenixMsiExec { 3010 }
        Install-PhoenixMsiPackage -Path 'C:\fake.msi' | Should -Be $true
    }

    It 'Install-PhoenixMsiPackage returns false on any other exit code' {
        Mock -ModuleName Installer Invoke-PhoenixMsiExec { 1603 }
        Install-PhoenixMsiPackage -Path 'C:\fake.msi' | Should -Be $false
    }

    It 'Install-PhoenixExePackage returns true on exit code 0' {
        Mock -ModuleName Installer Invoke-PhoenixExeInstaller { 0 }
        Install-PhoenixExePackage -Path 'C:\fake.exe' | Should -Be $true
    }

    It 'Install-PhoenixExePackage returns false on a non-zero exit code' {
        Mock -ModuleName Installer Invoke-PhoenixExeInstaller { 1 }
        Install-PhoenixExePackage -Path 'C:\fake.exe' | Should -Be $false
    }
}

Describe 'Install-PhoenixApplication' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'skips installation and reports PASS when already satisfied' {
        $manifest = [PSCustomObject]@{
            Name       = 'AlreadyThere'
            Installer  = 'Winget'
            Id         = 'Whatever.Id'
            Validate   = @([PSCustomObject]@{ Type = 'Command'; Value = 'Get-Command' })
        }
        Mock -ModuleName Installer Invoke-PhoenixWinGet { throw 'should not be called' }

        $result = Install-PhoenixApplication -Manifest $manifest

        $result.Status | Should -Be 'PASS'
        $result.Message | Should -Match 'Already installed'
    }

    It 'reports PASS after a successful install on the first attempt' {
        $manifest = [PSCustomObject]@{
            Name      = 'NeedsInstall'
            Installer = 'Winget'
            Id        = 'Needs.Install'
            Validate  = @([PSCustomObject]@{ Type = 'Command'; Value = 'Definitely-Not-Real-Before-Mock' })
        }
        $script:SatisfiedCheckCount = 0
        Mock -ModuleName Installer Invoke-PhoenixWinGet { 0 }
        Mock -ModuleName Installer Test-PhoenixApplicationSatisfied {
            $script:SatisfiedCheckCount++
            return ($script:SatisfiedCheckCount -gt 1)
        }

        $result = Install-PhoenixApplication -Manifest $manifest

        $result.Status | Should -Be 'PASS'
        Should -Invoke -ModuleName Installer Invoke-PhoenixWinGet -Times 1
    }

    It 'retries after a failed attempt and succeeds on the second' {
        $manifest = [PSCustomObject]@{
            Name      = 'FlakyInstall'
            Installer = 'Winget'
            Id        = 'Flaky.Install'
            Validate  = @([PSCustomObject]@{ Type = 'Command'; Value = 'Definitely-Not-Real-Before-Mock' })
        }
        $script:WinGetCallCount = 0
        Mock -ModuleName Installer Invoke-PhoenixWinGet {
            $script:WinGetCallCount++
            if ($script:WinGetCallCount -eq 1) { return 1 }
            return 0
        }
        Mock -ModuleName Installer Test-PhoenixApplicationSatisfied {
            return ($script:WinGetCallCount -ge 2)
        }

        $result = Install-PhoenixApplication -Manifest $manifest -MaxAttempts 3

        $result.Status | Should -Be 'PASS'
        Should -Invoke -ModuleName Installer Invoke-PhoenixWinGet -Times 2
    }

    It 'reports FAIL after exhausting all retries' {
        $manifest = [PSCustomObject]@{
            Name      = 'NeverWorks'
            Installer = 'Winget'
            Id        = 'Never.Works'
            Validate  = @([PSCustomObject]@{ Type = 'Command'; Value = 'Definitely-Not-Real-Before-Mock' })
        }
        Mock -ModuleName Installer Invoke-PhoenixWinGet { 1 }
        Mock -ModuleName Installer Test-PhoenixApplicationSatisfied { return $false }

        $result = Install-PhoenixApplication -Manifest $manifest -MaxAttempts 2

        $result.Status | Should -Be 'FAIL'
        Should -Invoke -ModuleName Installer Invoke-PhoenixWinGet -Times 2
    }

    It 'throws for an unknown installer backend' {
        $manifest = [PSCustomObject]@{
            Name      = 'Bad'
            Installer = 'Chocolatey'
            Validate  = @()
        }
        Mock -ModuleName Installer Test-PhoenixApplicationSatisfied { return $false }

        { Install-PhoenixApplication -Manifest $manifest -MaxAttempts 1 } | Should -Throw '*Chocolatey*'
    }
}

Describe 'Install-PhoenixApplications' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixBootstrap/PhoenixBootstrap.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'only installs manifests enabled by configuration' {
        $manifests = @(
            [PSCustomObject]@{ Name = 'Enabled'; Installer = 'Winget'; Id = 'A'; ConfigFlag = 'applications.InstallA'; Validate = @(); Dependencies = @(); RunOrder = 100 }
            [PSCustomObject]@{ Name = 'Disabled'; Installer = 'Winget'; Id = 'B'; ConfigFlag = 'applications.InstallB'; Validate = @(); Dependencies = @(); RunOrder = 100 }
        )
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ applications = [PSCustomObject]@{ InstallA = $true; InstallB = $false } } }

        Mock -ModuleName Installer Install-PhoenixApplication {
            param($Manifest, $MaxAttempts)
            [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'mocked' }
        }

        $results = Install-PhoenixApplications -Manifests $manifests -Configuration $config

        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'Enabled'
    }

    It 'installs enabled manifests in dependency order' {
        $manifests = @(
            [PSCustomObject]@{ Name = 'Second'; Installer = 'Winget'; Id = 'B'; ConfigFlag = 'applications.InstallB'; Validate = @(); Dependencies = @('First'); RunOrder = 100 }
            [PSCustomObject]@{ Name = 'First'; Installer = 'Winget'; Id = 'A'; ConfigFlag = 'applications.InstallA'; Validate = @(); Dependencies = @(); RunOrder = 100 }
        )
        $config = [PSCustomObject]@{ Modules = [PSCustomObject]@{ applications = [PSCustomObject]@{ InstallA = $true; InstallB = $true } } }

        $installOrder = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Installer Install-PhoenixApplication {
            param($Manifest, $MaxAttempts)
            $installOrder.Add($Manifest.Name)
            [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'mocked' }
        }

        $null = Install-PhoenixApplications -Manifests $manifests -Configuration $config

        $installOrder[0] | Should -Be 'First'
        $installOrder[1] | Should -Be 'Second'
    }
}

Describe 'Get-InstallerModuleDefinition' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'returns a definition with the Installer name and all four lifecycle stages' {
        $definition = Get-InstallerModuleDefinition

        $definition.Name | Should -Be 'Installer'
        $definition.Initialize | Should -Not -BeNullOrEmpty
        $definition.Validate | Should -Not -BeNullOrEmpty
        $definition.Execute | Should -Not -BeNullOrEmpty
        $definition.Verify | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-PhoenixProfile' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FixtureProfilesPath {
            param([hashtable]$Files)

            $path = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            foreach ($entry in $Files.GetEnumerator()) {
                Set-Content -Path (Join-Path $path $entry.Key) -Value $entry.Value
            }
            return $path
        }
    }

    It 'discovers all profiles when no name is given' {
        $path = New-FixtureProfilesPath -Files @{
            'a.json' = '{"Name":"A","Applications":["Git"]}'
            'b.json' = '{"Name":"B","Applications":["Steam"]}'
        }

        $profiles = Get-PhoenixProfile -ProfilesPath $path

        $profiles.Count | Should -Be 2
    }

    It 'selects a profile by name' {
        $path = New-FixtureProfilesPath -Files @{
            'a.json' = '{"Name":"A","Description":"first","Applications":["Git"]}'
            'b.json' = '{"Name":"B","Applications":["Steam"]}'
        }

        $result = Get-PhoenixProfile -ProfilesPath $path -ProfileName 'A'

        $result.Description | Should -Be 'first'
        $result.Applications | Should -Contain 'Git'
    }

    It 'throws with the available profile names when the requested one is missing' {
        $path = New-FixtureProfilesPath -Files @{
            'a.json' = '{"Name":"A","Applications":["Git"]}'
        }

        { Get-PhoenixProfile -ProfilesPath $path -ProfileName 'Ghost' } | Should -Throw '*Available profiles: A*'
    }

    It 'throws when a profile declares no applications' {
        $path = New-FixtureProfilesPath -Files @{
            'empty.json' = '{"Name":"Empty","Applications":[]}'
        }

        { Get-PhoenixProfile -ProfilesPath $path } | Should -Throw '*declares no applications*'
    }

    It 'throws on malformed profile JSON' {
        $path = New-FixtureProfilesPath -Files @{
            'broken.json' = '{ not valid json'
        }

        { Get-PhoenixProfile -ProfilesPath $path } | Should -Throw '*broken.json*'
    }

    It 'throws on duplicate profile names' {
        $path = New-FixtureProfilesPath -Files @{
            'x.json' = '{"Name":"Dup","Applications":["Git"]}'
            'y.json' = '{"Name":"Dup","Applications":["Steam"]}'
        }

        { Get-PhoenixProfile -ProfilesPath $path } | Should -Throw '*Dup*'
    }

    It 'parses the real shipped profiles without error, referencing only real manifests' {
        $repoProfiles = Get-PhoenixProfile -ProfilesPath (Resolve-Path "$PSScriptRoot/../profiles")
        $manifests = Get-PhoenixApplicationManifest -ManifestsPath (Resolve-Path "$PSScriptRoot/../modules/Installer/Applications")

        $repoProfiles.Name | Should -Contain 'Gaming'
        $repoProfiles.Name | Should -Contain 'Development'
        foreach ($repoProfile in $repoProfiles) {
            foreach ($appName in $repoProfile.Applications) {
                $manifests.Name | Should -Contain $appName
            }
        }
    }
}

Describe 'Expand-PhoenixProfileApplications' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        function New-FakeAppManifest {
            param([string]$Name, [string[]]$Dependencies = @())
            [PSCustomObject]@{ Name = $Name; Dependencies = $Dependencies; RunOrder = 100 }
        }
    }

    It 'returns exactly the listed manifests when there are no dependencies' {
        $manifests = @((New-FakeAppManifest 'A'), (New-FakeAppManifest 'B'), (New-FakeAppManifest 'C'))

        $selected = Expand-PhoenixProfileApplications -Manifests $manifests -ApplicationNames @('A', 'C')

        $selected.Count | Should -Be 2
        $selected.Name | Should -Contain 'A'
        $selected.Name | Should -Contain 'C'
    }

    It 'pulls in transitive dependencies not explicitly listed' {
        $manifests = @(
            (New-FakeAppManifest 'App' -Dependencies @('Lib'))
            (New-FakeAppManifest 'Lib' -Dependencies @('Base'))
            (New-FakeAppManifest 'Base')
        )

        $selected = Expand-PhoenixProfileApplications -Manifests $manifests -ApplicationNames @('App')

        $selected.Count | Should -Be 3
        $selected.Name | Should -Contain 'Base'
    }

    It 'throws when a profile references an application with no manifest' {
        $manifests = @((New-FakeAppManifest 'A'))

        { Expand-PhoenixProfileApplications -Manifests $manifests -ApplicationNames @('Ghost') } | Should -Throw '*Ghost*'
    }
}

Describe 'Invoke-PhoenixProfile' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Validation/Validation.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/PhoenixBootstrap/PhoenixBootstrap.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Installer/Installer.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'installs every application the real Gaming profile lists, without touching ConfigFlags' {
        Mock -ModuleName Installer Install-PhoenixApplication {
            param($Manifest, $MaxAttempts)
            [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'mocked' }
        }

        $results = Invoke-PhoenixProfile -ProfileName 'Gaming' -RootPath (Resolve-Path "$PSScriptRoot/..")

        $results.Count | Should -Be 3
        $results.Name | Should -Contain 'Steam'
        $results.Name | Should -Contain 'Epic Games Launcher'
        $results.Name | Should -Contain '7-Zip'
    }

    It 'throws cleanly for an unknown profile' {
        { Invoke-PhoenixProfile -ProfileName 'Ghost' -RootPath (Resolve-Path "$PSScriptRoot/..") } | Should -Throw '*Ghost*'
    }
}
