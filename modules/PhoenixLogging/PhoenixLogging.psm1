<#
    Phoenix Logging Engine - structured, leveled log output to console and disk.
    See docs/adr/0005-logging.md for the rationale behind this format.
#>

$script:PhoenixLogPath = $null

function Initialize-PhoenixLog {
    <#
        .SYNOPSIS
        Prepares the log file for this Phoenix run. Must be called before Write-PhoenixLog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory
    )

    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:PhoenixLogPath = Join-Path $LogDirectory "phoenix-$timestamp.log"
    New-Item -ItemType File -Path $script:PhoenixLogPath -Force | Out-Null
}

function Write-PhoenixLog {
    <#
        .SYNOPSIS
        Writes a structured, leveled log entry to the console and to the active log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [double]$Duration
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[$timestamp] $($Level.PadRight(7)) $Message"
    if ($PSBoundParameters.ContainsKey('Duration')) {
        $line += " (Duration: $([math]::Round($Duration, 1))s)"
    }

    $color = switch ($Level) {
        'INFO'    { 'Cyan' }
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
    }
    Write-Host $line -ForegroundColor $color

    if ($script:PhoenixLogPath) {
        Add-Content -Path $script:PhoenixLogPath -Value $line
    }
}

Export-ModuleMember -Function Initialize-PhoenixLog, Write-PhoenixLog
