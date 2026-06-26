BeforeAll {
    Import-Module "$PSScriptRoot/../modules/PhoenixLogging/PhoenixLogging.psd1" -Force
}

Describe 'Initialize-PhoenixLog / Write-PhoenixLog' {
    It 'creates a log file and writes a structured entry to it' {
        $logDir = Join-Path $TestDrive 'logs'
        Initialize-PhoenixLog -LogDirectory $logDir
        Write-PhoenixLog -Level INFO -Message 'Test message'

        $logFile = Get-ChildItem $logDir -Filter '*.log' | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        (Get-Content $logFile.FullName) | Should -Match 'INFO\s+Test message'
    }

    It 'includes duration when provided' {
        $logDir = Join-Path $TestDrive 'logs2'
        Initialize-PhoenixLog -LogDirectory $logDir
        Write-PhoenixLog -Level SUCCESS -Message 'Done' -Duration 1.23

        $logFile = Get-ChildItem $logDir -Filter '*.log' | Select-Object -First 1
        (Get-Content $logFile.FullName) | Should -Match 'Duration: 1\.2s'
    }
}
