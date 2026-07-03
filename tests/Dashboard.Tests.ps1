Describe 'Get-PhoenixGitCommit' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Dashboard/Dashboard.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')
    }

    It 'returns a commit hash inside a real git repository' {
        $commit = Get-PhoenixGitCommit -RootPath (Resolve-Path "$PSScriptRoot/..")

        $commit | Should -Not -Be 'unknown'
        $commit | Should -Match '^[0-9a-f]{7,}$'
    }

    It 'returns unknown, never throws, outside a git repository' {
        $nonRepo = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $nonRepo -Force | Out-Null

        Get-PhoenixGitCommit -RootPath $nonRepo | Should -Be 'unknown'
    }
}

Describe 'New-PhoenixDeploymentReport' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
        Import-Module "$PSScriptRoot/../modules/Dashboard/Dashboard.psd1" -Force
        Initialize-PhoenixLog -LogDirectory (Join-Path $TestDrive 'logs')

        Mock -ModuleName Dashboard Get-PhoenixGpuInfo {
            @([PSCustomObject]@{ Name = 'Fixture GPU'; Vendor = 'AMD' })
        }
        Mock -ModuleName Dashboard Get-PhoenixGitCommit { 'abc1234' }

        function New-FixtureHealth {
            param([string]$Module, [string]$Status = 'Healthy', [object[]]$Details = $null)
            [PSCustomObject]@{
                Module        = $Module
                Status        = $Status
                HealthPercent = if ($Status -eq 'Healthy') { 100 } else { 50 }
                LastRun       = (Get-Date).ToString('o')
                Issues        = @()
                Details       = $Details
            }
        }
    }

    It 'writes JSON and HTML files and returns their paths' {
        $reportsPath = Join-Path $TestDrive ([guid]::NewGuid())
        $health = @((New-FixtureHealth -Module 'Example'))

        $result = New-PhoenixDeploymentReport -ModuleHealth $health -RootPath (Resolve-Path "$PSScriptRoot/..") -DurationSeconds 12.34 -ReportsPath $reportsPath

        Test-Path $result.JsonPath | Should -Be $true
        Test-Path $result.HtmlPath | Should -Be $true
    }

    It 'produces parseable JSON carrying version, commit, machine, and module data' {
        $reportsPath = Join-Path $TestDrive ([guid]::NewGuid())
        $health = @((New-FixtureHealth -Module 'Example'))

        $result = New-PhoenixDeploymentReport -ModuleHealth $health -RootPath (Resolve-Path "$PSScriptRoot/..") -DurationSeconds 5 -ReportsPath $reportsPath
        $parsed = Get-Content $result.JsonPath -Raw | ConvertFrom-Json

        $parsed.GitCommit | Should -Be 'abc1234'
        $parsed.PhoenixVersion | Should -Match '^\d+\.\d+\.\d+$'
        $parsed.Machine.ComputerName | Should -Not -BeNullOrEmpty
        $parsed.Modules[0].Module | Should -Be 'Example'
        $parsed.Hardware.Gpus[0].Vendor | Should -Be 'AMD'
    }

    It 'counts failures and warnings across module statuses and per-item details' {
        $reportsPath = Join-Path $TestDrive ([guid]::NewGuid())
        $health = @(
            (New-FixtureHealth -Module 'A' -Status 'Warning' -Details @(
                [PSCustomObject]@{ Category = 'Application'; Name = 'X'; Status = 'FAIL'; Message = 'broke' }
                [PSCustomObject]@{ Category = 'Application'; Name = 'Y'; Status = 'WARN'; Message = 'meh' }
            ))
            (New-FixtureHealth -Module 'B' -Status 'Error')
        )

        $result = New-PhoenixDeploymentReport -ModuleHealth $health -RootPath (Resolve-Path "$PSScriptRoot/..") -ReportsPath $reportsPath

        $result.Report.Summary.Failures | Should -Be 2
        $result.Report.Summary.Warnings | Should -Be 2
    }

    It 'renders per-item details into the HTML and HTML-encodes untrusted text' {
        $reportsPath = Join-Path $TestDrive ([guid]::NewGuid())
        $health = @(
            (New-FixtureHealth -Module 'Installer' -Details @(
                [PSCustomObject]@{ Category = 'Application'; Name = 'Git'; Status = 'PASS'; Message = '<script>alert(1)</script>' }
            ))
        )

        $result = New-PhoenixDeploymentReport -ModuleHealth $health -RootPath (Resolve-Path "$PSScriptRoot/..") -ReportsPath $reportsPath
        $html = Get-Content $result.HtmlPath -Raw

        $html | Should -Match 'Installer'
        $html | Should -Match 'Git'
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;'
    }
}
