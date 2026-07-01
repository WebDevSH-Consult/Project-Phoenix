<#
    Phoenix Validation Engine (EPIC-04: System Validation & Self-Healing).

    Every check returns a structured PASS/WARN/FAIL result with diagnostic
    detail - never a silent skip, never an assumption about which hardware
    vendor or software is present. See docs/roadmap/EPIC-04-System-Validation.md
    and the "Validation First" standard in CONTRIBUTING.md.

    Depends on PhoenixLogging being imported first (for Write-PhoenixLog).
#>

function New-PhoenixValidationResult {
    <#
        .SYNOPSIS
        Builds a single structured validation result and logs it.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $logLevel = switch ($Status) {
        'PASS' { 'SUCCESS' }
        'WARN' { 'WARNING' }
        'FAIL' { 'ERROR' }
    }
    Write-PhoenixLog -Level $logLevel -Message "[Validation] $Category/$Name`: $Status - $Message"

    return [PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Status   = $Status
        Message  = $Message
    }
}

function Get-PhoenixGpuInfo {
    <#
        .SYNOPSIS
        Detects installed GPUs without assuming any particular vendor.

        .DESCRIPTION
        Wraps Get-CimInstance Win32_VideoController so it can be mocked in
        tests. Vendor is inferred from the adapter name; an adapter that
        doesn't match a known pattern is reported as Unknown rather than
        guessed at - Phoenix never assumes AMD or NVIDIA hardware.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $adapters = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue

    return @($adapters | ForEach-Object {
        $vendor = switch -Regex ($_.Name) {
            'AMD|Radeon' { 'AMD'; break }
            'NVIDIA|GeForce|Quadro' { 'NVIDIA'; break }
            'Intel' { 'Intel'; break }
            default { 'Unknown' }
        }
        [PSCustomObject]@{
            Name   = $_.Name
            Vendor = $vendor
        }
    })
}

function Test-PhoenixGpu {
    <#
        .SYNOPSIS
        Validates that at least one GPU is present and its vendor is known.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $gpus = @(Get-PhoenixGpuInfo)

    if ($gpus.Count -eq 0) {
        return New-PhoenixValidationResult -Category 'Hardware' -Name 'GPU' -Status 'FAIL' -Message 'No GPU detected.'
    }

    $unknown = @($gpus | Where-Object Vendor -eq 'Unknown')
    $summary = ($gpus | ForEach-Object { "$($_.Name) [$($_.Vendor)]" }) -join '; '

    if ($unknown.Count -gt 0) {
        return New-PhoenixValidationResult -Category 'Hardware' -Name 'GPU' -Status 'WARN' -Message "Detected but vendor unrecognised for at least one adapter: $summary"
    }

    return New-PhoenixValidationResult -Category 'Hardware' -Name 'GPU' -Status 'PASS' -Message "Detected: $summary"
}

function Test-PhoenixCommandAvailable {
    <#
        .SYNOPSIS
        Validates that a command is available on PATH. FAIL, not WARN - a
        missing required tool blocks dependent modules from working.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return New-PhoenixValidationResult -Category 'Windows' -Name $DisplayName -Status 'PASS' -Message "Found at $($command.Source)"
    }

    return New-PhoenixValidationResult -Category 'Windows' -Name $DisplayName -Status 'FAIL' -Message "'$CommandName' was not found on PATH."
}

function Test-PhoenixAppxPackageAvailable {
    <#
        .SYNOPSIS
        Validates whether a Microsoft Store (Appx) package is installed.

        .DESCRIPTION
        Absence is reported as WARN, not FAIL - Phoenix never assumes a
        Store package exists or is expected on every workstation.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $package = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    if ($package) {
        return New-PhoenixValidationResult -Category 'Windows' -Name $DisplayName -Status 'PASS' -Message "Installed (version $($package.Version))."
    }

    return New-PhoenixValidationResult -Category 'Windows' -Name $DisplayName -Status 'WARN' -Message "Not installed. This may be expected depending on workstation profile."
}

function Invoke-PhoenixValidationReport {
    <#
        .SYNOPSIS
        Runs every currently implemented validation check and returns the
        full set of results.

        .DESCRIPTION
        Application- and platform-specific checks (Steam, Epic, GameBar, AI
        tooling) are intentionally not implemented yet - see
        docs/roadmap/EPIC-04-System-Validation.md. Each lands alongside the
        installer module it validates so it can be tested against a real
        installation rather than assumed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    return @(
        Test-PhoenixGpu
        Test-PhoenixCommandAvailable -CommandName 'winget' -DisplayName 'WinGet'
        Test-PhoenixCommandAvailable -CommandName 'git' -DisplayName 'Git'
    )
}

function Get-ValidationModuleDefinition {
    <#
        .SYNOPSIS
        Returns the module definition hashtable consumed by
        Invoke-PhoenixModuleLifecycle, orchestrated via the Bootstrap Engine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name       = 'Validation'
        Initialize = { Write-PhoenixLog -Level INFO -Message '[Validation] Preparing to run system checks.' }
        Validate   = { $true }
        Execute    = {
            $script:PhoenixValidationResults = Invoke-PhoenixValidationReport
        }
        Verify     = {
            -not (@($script:PhoenixValidationResults) | Where-Object Status -eq 'FAIL')
        }
    }
}

Export-ModuleMember -Function Get-PhoenixGpuInfo, Test-PhoenixGpu, Test-PhoenixCommandAvailable, Test-PhoenixAppxPackageAvailable, Invoke-PhoenixValidationReport, Get-ValidationModuleDefinition
