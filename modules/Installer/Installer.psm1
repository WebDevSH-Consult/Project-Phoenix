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

#region Configuration gating

function Get-PhoenixConfigValue {
    <#
        .SYNOPSIS
        Resolves a dot-path (e.g. "applications.InstallGit") against a merged
        Phoenix configuration object. Returns $false if any segment is
        missing - an undeclared flag is never assumed to mean "install it".
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $current = $Configuration.Modules
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current -or $current.PSObject.Properties.Name -notcontains $segment) {
            return $false
        }
        $current = $current.$segment
    }

    return [bool]$current
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

        [int]$MaxAttempts = 2
    )

    if (Test-PhoenixApplicationSatisfied -Manifest $Manifest) {
        Write-PhoenixLog -Level SUCCESS -Message "[Installer] $($Manifest.Name): already installed."
        return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Already installed - no action taken.' }
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
            return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'PASS'; Message = "Installed successfully on attempt $attempt." }
        }

        Write-PhoenixLog -Level WARNING -Message "[Installer] $($Manifest.Name): attempt $attempt failed or post-install validation did not pass."
    }

    Write-PhoenixLog -Level ERROR -Message "[Installer] $($Manifest.Name): failed to install after $MaxAttempts attempt(s)."
    return [PSCustomObject]@{ Category = 'Application'; Name = $Manifest.Name; Status = 'FAIL'; Message = "Failed to install after $MaxAttempts attempt(s)." }
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
        [PSCustomObject]$Configuration
    )

    $enabled = @($Manifests | Where-Object { Get-PhoenixConfigValue -Configuration $Configuration -Path $_.ConfigFlag })
    Write-PhoenixLog -Level INFO -Message "[Installer] $($Manifests.Count) application manifest(s) discovered; $($enabled.Count) enabled by configuration."

    $ordered = Resolve-PhoenixModuleOrder -Manifests $enabled

    return @(
        foreach ($manifest in $ordered) {
            Install-PhoenixApplication -Manifest $manifest
        }
    )
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
    }
}

#endregion

Export-ModuleMember -Function Get-PhoenixApplicationManifest, Get-PhoenixConfigValue, Test-PhoenixApplicationSatisfied, Install-PhoenixWinGetPackage, Install-PhoenixMsiPackage, Install-PhoenixExePackage, Install-PhoenixApplication, Install-PhoenixApplications, Get-InstallerModuleDefinition
