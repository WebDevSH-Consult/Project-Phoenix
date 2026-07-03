<#
    Phoenix Health Dashboard (Roadmap 0.9 / ADR 0010).

    Generates an HTML + JSON deployment report at the end of every Bootstrap
    run: machine metadata, Phoenix version, git commit, GPU summary, run
    duration, per-module health, and per-item details (installs, settings,
    validation checks) surfaced through PhoenixCore's GetDetails channel.

    This is an engine module (like PhoenixLogging/PhoenixConfig): imported
    and called by Bootstrap.ps1 after orchestration, not orchestrated itself
    - the report summarizes results that only exist once orchestration has
    finished. No module.json by design; see ADR 0010.

    Depends on PhoenixLogging being imported first; imports PhoenixCore (for
    Get-PhoenixVersion) and Validation (for Get-PhoenixGpuInfo) itself.
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixCore\PhoenixCore.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1')

function Get-PhoenixGitCommit {
    <#
        .SYNOPSIS
        Returns the short git commit hash of RootPath, or 'unknown' when git
        or the repository is unavailable. Thin and mockable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try {
        $commit = & git -C $RootPath rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $commit) {
            return [string]$commit
        }
    }
    catch {
        # fall through to 'unknown' - a deployed Phoenix may not be a git checkout
    }
    return 'unknown'
}

function ConvertTo-PhoenixHtmlReport {
    <#
        .SYNOPSIS
        Renders a deployment report object as a single self-contained HTML
        document (inline CSS, no external assets, values HTML-encoded).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    function Encode([object]$value) {
        return [System.Net.WebUtility]::HtmlEncode("$value")
    }

    $statusColors = @{ Healthy = '#2e7d32'; Warning = '#f9a825'; Error = '#c62828'; Unknown = '#757575'; PASS = '#2e7d32'; WARN = '#f9a825'; FAIL = '#c62828' }

    $moduleRows = foreach ($module in $Report.Modules) {
        $color = if ($statusColors.ContainsKey("$($module.Status)")) { $statusColors["$($module.Status)"] } else { '#757575' }
        $issues = Encode(($module.Issues -join '; '))
        "<tr><td>$(Encode $module.Module)</td><td style=""color:$color;font-weight:bold"">$(Encode $module.Status)</td><td>$($module.HealthPercent)%</td><td>$issues</td></tr>"
    }

    $detailSections = foreach ($module in ($Report.Modules | Where-Object { $_.Details })) {
        $rows = foreach ($item in @($module.Details)) {
            $color = if ($statusColors.ContainsKey("$($item.Status)")) { $statusColors["$($item.Status)"] } else { '#757575' }
            "<tr><td>$(Encode $item.Category)</td><td>$(Encode $item.Name)</td><td style=""color:$color;font-weight:bold"">$(Encode $item.Status)</td><td>$(Encode $item.Message)</td></tr>"
        }
        @"
<h3>$(Encode $module.Module)</h3>
<table>
<tr><th>Category</th><th>Name</th><th>Status</th><th>Detail</th></tr>
$($rows -join "`n")
</table>
"@
    }

    $gpuRows = foreach ($gpu in @($Report.Hardware.Gpus)) {
        "<tr><td>$(Encode $gpu.Name)</td><td>$(Encode $gpu.Vendor)</td></tr>"
    }

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Phoenix Deployment Report - $(Encode $Report.Timestamp)</title>
<style>
body { font-family: 'Segoe UI', sans-serif; margin: 2rem auto; max-width: 60rem; color: #212121; }
h1 { border-bottom: 3px solid #e65100; padding-bottom: .3rem; }
table { border-collapse: collapse; width: 100%; margin-bottom: 1.5rem; }
th, td { border: 1px solid #ddd; padding: .45rem .6rem; text-align: left; font-size: .92rem; }
th { background: #f5f5f5; }
.summary span { display: inline-block; margin-right: 1.5rem; font-weight: bold; }
.meta td:first-child { font-weight: bold; width: 12rem; background: #fafafa; }
</style>
</head>
<body>
<h1>&#128293; Phoenix Deployment Report</h1>
<p class="summary">
<span>Failures: <span style="color:#c62828">$($Report.Summary.Failures)</span></span>
<span>Warnings: <span style="color:#f9a825">$($Report.Summary.Warnings)</span></span>
<span>Duration: $($Report.DurationSeconds)s</span>
</p>
<h2>Machine</h2>
<table class="meta">
<tr><td>Computer</td><td>$(Encode $Report.Machine.ComputerName)</td></tr>
<tr><td>User</td><td>$(Encode $Report.Machine.UserName)</td></tr>
<tr><td>Operating System</td><td>$(Encode $Report.Machine.OSVersion)</td></tr>
<tr><td>Phoenix Version</td><td>$(Encode $Report.PhoenixVersion)</td></tr>
<tr><td>Git Commit</td><td>$(Encode $Report.GitCommit)</td></tr>
<tr><td>Timestamp</td><td>$(Encode $Report.Timestamp)</td></tr>
</table>
<h2>Hardware</h2>
<table>
<tr><th>GPU</th><th>Vendor</th></tr>
$($gpuRows -join "`n")
</table>
<h2>Module Health</h2>
<table>
<tr><th>Module</th><th>Status</th><th>Health</th><th>Issues</th></tr>
$($moduleRows -join "`n")
</table>
<h2>Details</h2>
$($detailSections -join "`n")
</body>
</html>
"@
}

function New-PhoenixDeploymentReport {
    <#
        .SYNOPSIS
        Builds the deployment report from orchestration results and writes
        timestamped HTML and JSON files under ReportsPath.

        .DESCRIPTION
        Returns an object with the report itself plus the paths of the two
        files written. Called by Bootstrap.ps1 after Invoke-PhoenixOrchestration;
        see ADR 0010.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$ModuleHealth,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [double]$DurationSeconds = 0,

        [string]$ReportsPath = (Join-Path $RootPath 'reports')
    )

    $allDetails = @($ModuleHealth | Where-Object { $_.Details } | ForEach-Object { @($_.Details) })
    $failures = @($allDetails | Where-Object Status -eq 'FAIL').Count + @($ModuleHealth | Where-Object Status -eq 'Error').Count
    $warnings = @($allDetails | Where-Object Status -eq 'WARN').Count + @($ModuleHealth | Where-Object Status -eq 'Warning').Count

    $report = [PSCustomObject]@{
        Timestamp       = (Get-Date).ToString('o')
        PhoenixVersion  = (Get-PhoenixVersion -RootPath $RootPath).Version
        GitCommit       = Get-PhoenixGitCommit -RootPath $RootPath
        DurationSeconds = [math]::Round($DurationSeconds, 1)
        Machine         = [PSCustomObject]@{
            ComputerName = [System.Environment]::MachineName
            UserName     = [System.Environment]::UserName
            OSVersion    = [System.Environment]::OSVersion.VersionString
        }
        Hardware        = [PSCustomObject]@{
            Gpus = @(Get-PhoenixGpuInfo)
        }
        Summary         = [PSCustomObject]@{
            Failures = $failures
            Warnings = $warnings
        }
        Modules         = $ModuleHealth
    }

    if (-not (Test-Path -LiteralPath $ReportsPath)) {
        New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $ReportsPath "deployment-report-$stamp.json"
    $htmlPath = Join-Path $ReportsPath "deployment-report-$stamp.html"

    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding utf8
    ConvertTo-PhoenixHtmlReport -Report $report | Set-Content -Path $htmlPath -Encoding utf8

    Write-PhoenixLog -Level SUCCESS -Message "[Dashboard] Deployment report written: $htmlPath"

    return [PSCustomObject]@{
        Report   = $report
        JsonPath = $jsonPath
        HtmlPath = $htmlPath
    }
}

Export-ModuleMember -Function Get-PhoenixGitCommit, ConvertTo-PhoenixHtmlReport, New-PhoenixDeploymentReport
