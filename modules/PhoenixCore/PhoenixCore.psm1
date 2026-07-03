<#
    Phoenix Core - the module lifecycle dispatcher every Phoenix module runs through.

    Every module is invoked via Invoke-PhoenixModuleLifecycle, which enforces the
    Initialise -> Validate -> Execute -> Verify -> Log -> Report lifecycle defined in
    ARCHITECTURE.md. No module talks to another module directly; everything routes
    through here, and every run returns a health object the Dashboard module can
    consume.

    Depends on PhoenixLogging being imported first (for Write-PhoenixLog).
#>

function Get-PhoenixVersion {
    <#
        .SYNOPSIS
        Returns the current Project Phoenix version as a structured object.

        .DESCRIPTION
        Reads the VERSION file at the repository root - the single source of
        truth for the project's version - and returns it alongside its
        Major/Minor/Patch components.

        .PARAMETER RootPath
        The Project Phoenix repository root - the directory containing the
        VERSION file.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $versionPath = Join-Path $RootPath 'VERSION'
    if (-not (Test-Path -LiteralPath $versionPath)) {
        throw "VERSION file not found at $versionPath"
    }

    $versionString = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    $parts = $versionString -split '\.'

    return [PSCustomObject]@{
        Version = $versionString
        Major   = [int]$parts[0]
        Minor   = [int]$parts[1]
        Patch   = [int]$parts[2]
    }
}

function Test-PhoenixElevated {
    <#
        .SYNOPSIS
        Reports whether the current process holds administrator rights.

        .DESCRIPTION
        Phoenix never auto-elevates (ADR 0013): capabilities that need
        rights the process doesn't have are skipped with a clear WARN and
        a "re-run elevated" recommendation, never attempted blindly.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-PhoenixModuleLifecycle {
    <#
        .SYNOPSIS
        Runs a single module through the standard Phoenix lifecycle and returns its health object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [scriptblock]$Initialize,
        [scriptblock]$Validate,
        [scriptblock]$Execute,
        [scriptblock]$Verify,

        # Optional: returns the module's per-item results (installs, settings,
        # checks) for the deployment report. Attached to the health object's
        # Details property after the lifecycle completes; a failure here
        # degrades to Details = $null, never a module failure. See ADR 0010.
        [scriptblock]$GetDetails
    )

    $start = Get-Date
    $health = [PSCustomObject]@{
        Module        = $Name
        Status        = 'Unknown'
        HealthPercent = 0
        LastRun       = $start.ToString('o')
        Issues        = [System.Collections.Generic.List[string]]::new()
        Details       = $null
    }

    try {
        Write-PhoenixLog -Level INFO -Message "[$Name] Initialising..."
        if ($Initialize) { & $Initialize }

        Write-PhoenixLog -Level INFO -Message "[$Name] Validating..."
        $isValid = $true
        if ($Validate) { $isValid = [bool](& $Validate) }
        if (-not $isValid) {
            throw 'Validation failed.'
        }

        Write-PhoenixLog -Level INFO -Message "[$Name] Executing..."
        if ($Execute) { & $Execute }

        Write-PhoenixLog -Level INFO -Message "[$Name] Verifying..."
        $verified = $true
        if ($Verify) { $verified = [bool](& $Verify) }

        $duration = ((Get-Date) - $start).TotalSeconds

        if ($verified) {
            $health.Status = 'Healthy'
            $health.HealthPercent = 100
            Write-PhoenixLog -Level SUCCESS -Message "[$Name] Completed" -Duration $duration
        }
        else {
            $health.Status = 'Warning'
            $health.HealthPercent = 50
            $health.Issues.Add('Verification step did not confirm success.')
            Write-PhoenixLog -Level WARNING -Message "[$Name] Completed with unverified result" -Duration $duration
        }
    }
    catch {
        $health.Status = 'Error'
        $health.HealthPercent = 0
        $health.Issues.Add($_.Exception.Message)
        Write-PhoenixLog -Level ERROR -Message "[$Name] $($_.Exception.Message)"
    }

    if ($GetDetails) {
        try {
            $health.Details = & $GetDetails
        }
        catch {
            Write-PhoenixLog -Level WARNING -Message "[$Name] GetDetails failed: $($_.Exception.Message)"
        }
    }

    return $health
}

function Invoke-PhoenixBootstrap {
    <#
        .SYNOPSIS
        Runs every registered module through Invoke-PhoenixModuleLifecycle and reports
        an aggregate health summary.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Modules
    )

    $results = foreach ($module in $Modules) {
        Invoke-PhoenixModuleLifecycle @module
    }

    Write-PhoenixLog -Level INFO -Message '--- Phoenix Health Report ---'
    foreach ($result in $results) {
        Write-PhoenixLog -Level INFO -Message "$($result.Module): $($result.HealthPercent)% ($($result.Status))"
    }

    return $results
}

Export-ModuleMember -Function Get-PhoenixVersion, Test-PhoenixElevated, Invoke-PhoenixModuleLifecycle, Invoke-PhoenixBootstrap
