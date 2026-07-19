<#
    Phoenix Application Deployment Engine (Roadmap 0.6 / ADR 0007).

    Every application is data (a JSON manifest under Applications/), not a
    bespoke script. Adding an application means adding a manifest - no
    PowerShell changes. See modules/Installer/README.md and
    docs/adr/0007-application-deployment-engine.md for the full design.

    Depends on PhoenixLogging, PhoenixConfig, PhoenixBootstrap, and
    Validation being importable (this module imports them itself where
    needed, rather than relying on orchestration having already done so).
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1')

#region Backends - thin, mockable wrappers around the actual install invocation

function Invoke-PhoenixWinGet {
    <#
        .SYNOPSIS
        Thin, mockable wrapper around `winget install`.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    & winget @ArgumentList | Out-Null
    return $LASTEXITCODE
}

function Invoke-PhoenixWinGetUpgradeQuery {
    <#
        .SYNOPSIS
        Thin, mockable, read-only wrapper around `winget upgrade` for a single
        package. Captures output (unlike Invoke-PhoenixWinGet) so callers can
        tell whether an upgrade is available. Changes nothing.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $output = & winget upgrade --id $PackageId --exact --accept-source-agreements 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output -join "`n"
    }
}

function Install-PhoenixWinGetPackage {
    <#
        .SYNOPSIS
        Installs a package by WinGet package ID.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $exitCode = Invoke-PhoenixWinGet -ArgumentList @('install', '--id', $PackageId, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    return ($exitCode -eq 0)
}

function Invoke-PhoenixMsiExec {
    <#
        .SYNOPSIS
        Thin, mockable wrapper around msiexec.exe.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}

function Install-PhoenixMsiPackage {
    <#
        .SYNOPSIS
        Installs an MSI package silently.

        .DESCRIPTION
        Exit code 3010 (success, reboot required) is treated as success -
        the install itself succeeded even though a restart is pending.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    $exitCode = Invoke-PhoenixMsiExec -ArgumentList (@('/i', "`"$Path`"", '/quiet', '/norestart') + $Arguments)
    return ($exitCode -eq 0 -or $exitCode -eq 3010)
}

function Invoke-PhoenixExeInstaller {
    <#
        .SYNOPSIS
        Thin, mockable wrapper around Start-Process for EXE installers.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$ArgumentList = @()
    )

    $process = Start-Process -FilePath $Path -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}

function Install-PhoenixExePackage {
    <#
        .SYNOPSIS
        Runs a silent EXE installer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    $exitCode = Invoke-PhoenixExeInstaller -Path $Path -ArgumentList $Arguments
    return ($exitCode -eq 0)
}

function Update-PhoenixWinGetPackage {
    <#
        .SYNOPSIS
        Upgrades a package by WinGet package ID (`winget upgrade`).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $exitCode = Invoke-PhoenixWinGet -ArgumentList @('upgrade', '--id', $PackageId, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    return ($exitCode -eq 0)
}

function Uninstall-PhoenixWinGetPackage {
    <#
        .SYNOPSIS
        Uninstalls a package by WinGet package ID (`winget uninstall`).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $exitCode = Invoke-PhoenixWinGet -ArgumentList @('uninstall', '--id', $PackageId, '--exact', '--silent')
    return ($exitCode -eq 0)
}

function Uninstall-PhoenixMsiPackage {
    <#
        .SYNOPSIS
        Uninstalls an MSI package silently (`msiexec /x`).

        .DESCRIPTION
        Exit code 3010 (success, reboot required) is treated as success.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $exitCode = Invoke-PhoenixMsiExec -ArgumentList @('/x', "`"$Path`"", '/quiet', '/norestart')
    return ($exitCode -eq 0 -or $exitCode -eq 3010)
}

#endregion

#region Manifest discovery

function Get-PhoenixApplicationManifest {
    <#
        .SYNOPSIS
        Discovers and validates every application manifest under ManifestsPath.

        .DESCRIPTION
        Required fields: Name, Installer (Winget|MSI|EXE), ConfigFlag, Validate.
        Id/Source/Arguments are backend-specific and optional at the schema
        level (WinGet needs Id; MSI/EXE need Source). Dependencies and
        RunOrder are optional, defaulting to an empty list and 100
        respectively, matching Resolve-PhoenixModuleOrder's expectations so
        application ordering can reuse it directly.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestsPath
    )

    $manifests = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenNames = @{}

    $files = Get-ChildItem -LiteralPath $ManifestsPath -Filter '*.json' -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-PhoenixLog -Level ERROR -Message "Failed to parse application manifest '$($file.Name)': $($_.Exception.Message)"
            throw "Failed to parse application manifest '$($file.Name)': $($_.Exception.Message)"
        }

        foreach ($field in @('Name', 'Installer', 'ConfigFlag', 'Validate')) {
            if ($raw.PSObject.Properties.Name -notcontains $field) {
                Write-PhoenixLog -Level ERROR -Message "Application manifest '$($file.Name)' is missing required field '$field'."
                throw "Application manifest '$($file.Name)' is missing required field '$field'."
            }
        }

        if ($raw.Installer -notin @('Winget', 'MSI', 'EXE')) {
            Write-PhoenixLog -Level ERROR -Message "Application manifest '$($file.Name)' has an unknown Installer type '$($raw.Installer)'."
            throw "Application manifest '$($file.Name)' has an unknown Installer type '$($raw.Installer)'."
        }

        if ($seenNames.ContainsKey($raw.Name)) {
            Write-PhoenixLog -Level ERROR -Message "Duplicate application name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
            throw "Duplicate application name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
        }
        $seenNames[$raw.Name] = $file.Name

        $dependencies = @()
        if ($raw.PSObject.Properties.Name -contains 'Dependencies' -and $null -ne $raw.Dependencies) {
            $dependencies = @($raw.Dependencies)
        }
        $runOrder = 100
        if ($raw.PSObject.Properties.Name -contains 'RunOrder') {
            $runOrder = [int]$raw.RunOrder
        }

        $manifests.Add([PSCustomObject]@{
            Name         = [string]$raw.Name
            Installer    = [string]$raw.Installer
            Id           = if ($raw.PSObject.Properties.Name -contains 'Id') { [string]$raw.Id } else { $null }
            Source       = if ($raw.PSObject.Properties.Name -contains 'Source') { [string]$raw.Source } else { $null }
            Arguments    = if ($raw.PSObject.Properties.Name -contains 'Arguments') { @($raw.Arguments) } else { @() }
            ConfigFlag   = [string]$raw.ConfigFlag
            Validate     = @($raw.Validate)
            Dependencies = $dependencies
            RunOrder     = $runOrder
        })
    }

    return $manifests.ToArray()
}

#endregion

#region Install + validate + retry

function Test-PhoenixApplicationSatisfied {
    <#
        .SYNOPSIS
        Checks whether an application's Validate probes all currently PASS.

        .DESCRIPTION
        Every probe must PASS - WARN is treated as "not yet satisfied" here,
        even though Validation's own primitives treat WARN as informational
        for system-wide reporting. Install verification needs a strict
        yes/no answer; the system-wide report needs the more lenient one.
        Both are correct for their own purpose.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $results = foreach ($probe in $Manifest.Validate) {
        switch ($probe.Type) {
            'Command' { Test-PhoenixCommandAvailable -CommandName $probe.Value -DisplayName $Manifest.Name }
            'AppxPackage' { Test-PhoenixAppxPackageAvailable -PackageName $probe.Value -DisplayName $Manifest.Name }
            'Path' { Test-PhoenixPathExists -Path $probe.Value -DisplayName $Manifest.Name }
            'WinGetPackage' { Test-PhoenixWinGetPackageInstalled -PackageId $probe.Value -DisplayName $Manifest.Name }
            default { throw "Unknown validation probe type '$($probe.Type)' in manifest '$($Manifest.Name)'." }
        }
    }

    return -not (@($results) | Where-Object Status -ne 'PASS')
}

function Test-PhoenixApplicationOutdated {
    <#
        .SYNOPSIS
        Read-only check: does WinGet report a newer version available for this
        (installed) application? Used by the State Engine's version-currency
        drift domain (ADR 0018).

        .DESCRIPTION
        Only WinGet-backed applications with an Id can be checked - MSI/EXE
        backends carry no upgrade channel Phoenix can query, so they report
        $false (no version signal, never a fabricated one). Assumes the app is
        installed; callers check presence first. A parse/query failure returns
        $false so an uncertain result never invents drift. Changes nothing.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    if ($Manifest.Installer -ne 'Winget' -or -not $Manifest.Id) { return $false }

    $result = Invoke-PhoenixWinGetUpgradeQuery -PackageId $Manifest.Id
    if ($result.ExitCode -ne 0) { return $false }

    # An available upgrade lists the package Id alongside a version column.
    # winget prints "No available upgrade found." / "No installed package
    # found matching input criteria." when there is nothing to do.
    if ($result.Output -match 'No available upgrade' -or $result.Output -match 'No installed package') { return $false }
    return [bool]($result.Output -match [regex]::Escape($Manifest.Id))
}

function Install-PhoenixApplication {
    <#
        .SYNOPSIS
        Installs a single application: skip if already satisfied, otherwise
        install via its declared backend, retrying and re-validating after
        every attempt.

        .DESCRIPTION
        Returns a result in the same {Category, Name, Status, Message} shape
        used throughout Phoenix (see modules/Validation), so installer
        results and validation results compose into one consistent
        vocabulary.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest,

        [int]$MaxAttempts = 2,

        # Preview only: report what would happen, invoke no backend (ADR 0014).
        [switch]$DryRun
    )

    if ($DryRun) {
        if (Test-PhoenixApplicationSatisfied -Manifest $Manifest) {
            Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifest.Name): DRY RUN - already installed, no action would be taken."
            return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'DRY RUN: already installed - no action would be taken.'; Changed = $false }
        }
        $target = if ($Manifest.Installer -eq 'Winget') { "WinGet ($($Manifest.Id))" } else { "$($Manifest.Installer) ($($Manifest.Source))" }
        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): DRY RUN - would install via $target."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'WARN'; Message = "DRY RUN: would install via $target."; Changed = $false }
    }

    if (Test-PhoenixApplicationSatisfied -Manifest $Manifest) {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): already installed."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Already installed - no action taken.'; Changed = $false }
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifest.Name): installing (attempt $attempt of $MaxAttempts) via $($Manifest.Installer)..."

        $backendSucceeded = switch ($Manifest.Installer) {
            'Winget' { Install-PhoenixWinGetPackage -PackageId $Manifest.Id }
            'MSI' { Install-PhoenixMsiPackage -Path $Manifest.Source -Arguments $Manifest.Arguments }
            'EXE' { Install-PhoenixExePackage -Path $Manifest.Source -Arguments $Manifest.Arguments }
            default { throw "Unknown installer backend '$($Manifest.Installer)' for '$($Manifest.Name)'." }
        }

        if ($backendSucceeded -and (Test-PhoenixApplicationSatisfied -Manifest $Manifest)) {
            Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): installed and validated (attempt $attempt)."
            return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = "Installed successfully on attempt $attempt."; Changed = $true }
        }

        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): attempt $attempt failed or post-install validation did not pass."
    }

    Write-PhoenixLog -Level ERROR -Message "[Installer] $($Manifest.Name): failed to install after $MaxAttempts attempt(s)."
    return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'FAIL'; Message = "Failed to install after $MaxAttempts attempt(s)."; Changed = $false }
}

function Update-PhoenixApplication {
    <#
        .SYNOPSIS
        Upgrades an already-installed application (ADR 0014).

        .DESCRIPTION
        WinGet is fully supported. A not-installed application reports WARN
        (nothing to upgrade); non-WinGet backends report WARN (upgrade not
        supported), never a silent no-op. Operator-invoked - not part of the
        orchestrated bootstrap run.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    if ($Manifest.Installer -ne 'Winget') {
        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): upgrade not supported for the $($Manifest.Installer) backend."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'WARN'; Message = "Upgrade not supported for the $($Manifest.Installer) backend." }
    }

    if (-not (Test-PhoenixApplicationSatisfied -Manifest $Manifest)) {
        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): not installed - nothing to upgrade."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'WARN'; Message = 'Not installed - nothing to upgrade (use install).' }
    }

    Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifest.Name): upgrading via WinGet..."
    if (Update-PhoenixWinGetPackage -PackageId $Manifest.Id) {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): upgraded (or already current)."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Upgraded (or already at the latest version).' }
    }

    Write-PhoenixLog -Level ERROR -Message "[Installer] $($Manifest.Name): upgrade failed."
    return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'FAIL'; Message = 'Upgrade failed.' }
}

function Uninstall-PhoenixApplication {
    <#
        .SYNOPSIS
        Removes an application and verifies it is actually gone afterward
        (ADR 0014).

        .DESCRIPTION
        WinGet and MSI are supported; EXE reports WARN (no standard silent
        uninstall path). Uninstalling a not-installed application is
        idempotent (PASS - nothing to do). Operator-invoked - not part of
        the orchestrated bootstrap run.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    if (-not (Test-PhoenixApplicationSatisfied -Manifest $Manifest)) {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): not installed - nothing to uninstall."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Not installed - nothing to uninstall.' }
    }

    if ($Manifest.Installer -eq 'EXE') {
        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): uninstall not supported for the EXE backend."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'WARN'; Message = 'Uninstall not supported for the EXE backend.' }
    }

    Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifest.Name): uninstalling via $($Manifest.Installer)..."
    $backendSucceeded = switch ($Manifest.Installer) {
        'Winget' { Uninstall-PhoenixWinGetPackage -PackageId $Manifest.Id }
        'MSI' { Uninstall-PhoenixMsiPackage -Path $Manifest.Source }
        default { throw "Unknown installer backend '$($Manifest.Installer)' for '$($Manifest.Name)'." }
    }

    if ($backendSucceeded -and -not (Test-PhoenixApplicationSatisfied -Manifest $Manifest)) {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): uninstalled and verified."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Uninstalled successfully.' }
    }

    Write-PhoenixLog -Level ERROR -Message "[Installer] $($Manifest.Name): uninstall did not remove the application."
    return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'FAIL'; Message = 'Uninstall did not remove the application.' }
}

function Install-PhoenixApplications {
    <#
        .SYNOPSIS
        Installs every application manifest enabled by configuration, in
        dependency order.

        .DESCRIPTION
        Filters manifests by their ConfigFlag against Configuration, then
        reuses Resolve-PhoenixModuleOrder (from PhoenixBootstrap) to order
        them - that function is already generic over Name/Dependencies/
        RunOrder, so a second topological sort would be pure duplication.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Manifests,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        # Escape hatch for the preflight safety gate (ADR 0012). Off by
        # default: no system-level installation runs on a non-idle Windows
        # servicing state.
        [switch]$SkipPreflight,

        # Preview only: report what would happen, invoke no backend (ADR 0014).
        # A dry run changes nothing, so it also skips the preflight gate.
        [switch]$DryRun
    )

    if (-not $DryRun -and -not $SkipPreflight) {
        $preflight = Get-PhoenixPreflightState
        if (-not $preflight.Safe) {
            Write-PhoenixLog -Level ERROR -Message '[Installer] Preflight failed - system is not in a safe state for installation. Nothing will be installed.'
            return @($preflight.Results | Where-Object Status -eq 'FAIL')
        }
    }

    $enabled = @($Manifests | Where-Object { Get-PhoenixConfigValue -Configuration $Configuration -Path $_.ConfigFlag })
    $mode = if ($DryRun) { ' (dry run)' } else { '' }
    Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifests.Count) application manifest(s) discovered; $($enabled.Count) enabled by configuration$mode."

    $ordered = Resolve-PhoenixModuleOrder -Manifests $enabled

    return @(
        foreach ($manifest in $ordered) {
            Install-PhoenixApplication -Manifest $manifest -DryRun:$DryRun
        }
    )
}

#endregion

#region Workstation profiles (ADR 0008)

function Get-PhoenixProfile {
    <#
        .SYNOPSIS
        Discovers workstation profiles under ProfilesPath, optionally
        selecting one by name.

        .DESCRIPTION
        Each profile is a JSON file with Name, Description, and a non-empty
        Applications array of application manifest names. Without
        -ProfileName, returns every discovered profile; with it, returns the
        matching profile or throws, listing what was available.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilesPath,

        [string]$ProfileName
    )

    $profiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenNames = @{}

    $files = Get-ChildItem -LiteralPath $ProfilesPath -Filter '*.json' -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-PhoenixLog -Level ERROR -Message "Failed to parse profile '$($file.Name)': $($_.Exception.Message)"
            throw "Failed to parse profile '$($file.Name)': $($_.Exception.Message)"
        }

        foreach ($field in @('Name', 'Applications')) {
            if ($raw.PSObject.Properties.Name -notcontains $field) {
                Write-PhoenixLog -Level ERROR -Message "Profile '$($file.Name)' is missing required field '$field'."
                throw "Profile '$($file.Name)' is missing required field '$field'."
            }
        }

        if (@($raw.Applications).Count -eq 0) {
            Write-PhoenixLog -Level ERROR -Message "Profile '$($file.Name)' declares no applications."
            throw "Profile '$($file.Name)' declares no applications."
        }

        if ($seenNames.ContainsKey($raw.Name)) {
            Write-PhoenixLog -Level ERROR -Message "Duplicate profile name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
            throw "Duplicate profile name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
        }
        $seenNames[$raw.Name] = $file.Name

        $description = ''
        if ($raw.PSObject.Properties.Name -contains 'Description') {
            $description = [string]$raw.Description
        }

        $profiles.Add([PSCustomObject]@{
            Name         = [string]$raw.Name
            Description  = $description
            Applications = @($raw.Applications)
        })
    }

    if (-not $PSBoundParameters.ContainsKey('ProfileName') -or [string]::IsNullOrEmpty($ProfileName)) {
        return $profiles.ToArray()
    }

    $match = $profiles | Where-Object { $_.Name -eq $ProfileName }
    if (-not $match) {
        $available = if ($profiles.Count -gt 0) { ($profiles.Name -join ', ') } else { 'none' }
        Write-PhoenixLog -Level ERROR -Message "Profile '$ProfileName' not found. Available profiles: $available."
        throw "Profile '$ProfileName' not found. Available profiles: $available."
    }

    return $match
}

function Expand-PhoenixProfileApplications {
    <#
        .SYNOPSIS
        Resolves a profile's application names to their manifests, pulling
        in transitive dependencies not explicitly listed.

        .DESCRIPTION
        An application name (listed directly or reached via a dependency)
        with no matching manifest fails loudly - a profile may only promise
        what Phoenix can actually install.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Manifests,

        [Parameter(Mandatory)]
        [string[]]$ApplicationNames
    )

    $byName = @{}
    foreach ($manifest in $Manifests) { $byName[$manifest.Name] = $manifest }

    $selected = [ordered]@{}
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($name in $ApplicationNames) { $queue.Enqueue($name) }

    while ($queue.Count -gt 0) {
        $name = $queue.Dequeue()
        if ($selected.Contains($name)) { continue }

        if (-not $byName.ContainsKey($name)) {
            Write-PhoenixLog -Level ERROR -Message "Profile references application '$name', which has no manifest under Applications/."
            throw "Profile references application '$name', which has no manifest under Applications/."
        }

        $selected[$name] = $byName[$name]
        foreach ($dependency in $byName[$name].Dependencies) {
            $queue.Enqueue($dependency)
        }
    }

    return @($selected.Values)
}

function Invoke-PhoenixProfile {
    <#
        .SYNOPSIS
        Installs every application a workstation profile lists, plus
        transitive dependencies, in dependency order.

        .DESCRIPTION
        A profile is an explicit selection: it installs exactly what it
        lists regardless of ConfigFlag values, which gate only the default
        orchestrated run. Inherits Install-PhoenixApplication's idempotency,
        retry, and post-install validation unchanged. See ADR 0008.

        .EXAMPLE
        Invoke-PhoenixProfile -ProfileName Gaming
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProfileName,

        [string]$RootPath,

        [int]$MaxAttempts = 2,

        # Escape hatch for the preflight safety gate (ADR 0012). Off by
        # default: no system-level installation runs on a non-idle Windows
        # servicing state.
        [switch]$SkipPreflight,

        # Preview only: report what the profile would install, invoke no
        # backend (ADR 0014). Skips the preflight gate - nothing changes.
        [switch]$DryRun
    )

    Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\PhoenixBootstrap\PhoenixBootstrap.psd1') -Force

    if (-not $RootPath) {
        $RootPath = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    }

    if (-not $DryRun -and -not $SkipPreflight) {
        $preflight = Get-PhoenixPreflightState
        if (-not $preflight.Safe) {
            Write-PhoenixLog -Level ERROR -Message "[Installer] Preflight failed - system is not in a safe state for installation. Profile '$ProfileName' will not be applied."
            return @($preflight.Results | Where-Object Status -eq 'FAIL')
        }
    }

    $workstationProfile = Get-PhoenixProfile -ProfilesPath (Join-Path $RootPath 'profiles') -ProfileName $ProfileName
    $mode = if ($DryRun) { ' (dry run)' } else { '' }
    Write-PhoenixLog -Level INFO -Message "[Installer] Applying profile '$($workstationProfile.Name)'$mode`: $($workstationProfile.Applications -join ', ')"

    $manifests = Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $PSScriptRoot 'Applications')
    $selected = Expand-PhoenixProfileApplications -Manifests $manifests -ApplicationNames $workstationProfile.Applications
    $ordered = Resolve-PhoenixModuleOrder -Manifests $selected

    $results = @(
        foreach ($manifest in $ordered) {
            Install-PhoenixApplication -Manifest $manifest -MaxAttempts $MaxAttempts -DryRun:$DryRun
        }
    )

    $failed = @($results | Where-Object Status -eq 'FAIL')
    if ($failed.Count -gt 0) {
        Write-PhoenixLog -Level WARNING -Message "[Installer] Profile '$($workstationProfile.Name)' completed with $($failed.Count) failure(s) out of $($results.Count) application(s)."
    }
    else {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] Profile '$($workstationProfile.Name)' applied: $($results.Count) application(s) verified."
    }

    return $results
}

#endregion

#region Bootstrap Engine integration

function Get-InstallerModuleDefinition {
    <#
        .SYNOPSIS
        Returns the module definition hashtable consumed by
        Invoke-PhoenixModuleLifecycle, orchestrated via the Bootstrap Engine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name       = 'Installer'
        Initialize = {
            $script:PhoenixInstallResults = @()
            Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1') -Force
            Write-PhoenixLog -Level INFO -Message '[Installer] Preparing application deployment engine.'
        }
        Validate   = { $true }
        Execute    = {
            Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1') -Force
            Import-Module (Join-Path $PSScriptRoot '..\PhoenixBootstrap\PhoenixBootstrap.psd1') -Force

            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
            $configuration = Get-PhoenixConfiguration -RootPath $repoRoot
            $manifests = Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $PSScriptRoot 'Applications')

            $script:PhoenixInstallResults = Install-PhoenixApplications -Manifests $manifests -Configuration $configuration
        }
        Verify     = {
            -not (@($script:PhoenixInstallResults) | Where-Object Status -eq 'FAIL')
        }
        GetDetails = { $script:PhoenixInstallResults }
    }
}

#endregion

Export-ModuleMember -Function Get-PhoenixApplicationManifest, Test-PhoenixApplicationSatisfied, Test-PhoenixApplicationOutdated, Install-PhoenixWinGetPackage, Install-PhoenixMsiPackage, Install-PhoenixExePackage, Update-PhoenixWinGetPackage, Uninstall-PhoenixWinGetPackage, Uninstall-PhoenixMsiPackage, Install-PhoenixApplication, Update-PhoenixApplication, Uninstall-PhoenixApplication, Install-PhoenixApplications, Get-PhoenixProfile, Expand-PhoenixProfileApplications, Invoke-PhoenixProfile, Get-InstallerModuleDefinition
