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

        [int]$MaxAttempts = 2
    )

    Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\PhoenixBootstrap\PhoenixBootstrap.psd1') -Force

    if (-not $RootPath) {
        $RootPath = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    }

    $workstationProfile = Get-PhoenixProfile -ProfilesPath (Join-Path $RootPath 'profiles') -ProfileName $ProfileName
    Write-PhoenixLog -Level INFO -Message "[Installer] Applying profile '$($workstationProfile.Name)': $($workstationProfile.Applications -join ', ')"

    $manifests = Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $PSScriptRoot 'Applications')
    $selected = Expand-PhoenixProfileApplications -Manifests $manifests -ApplicationNames $workstationProfile.Applications
    $ordered = Resolve-PhoenixModuleOrder -Manifests $selected

    $results = @(
        foreach ($manifest in $ordered) {
            Install-PhoenixApplication -Manifest $manifest -MaxAttempts $MaxAttempts
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

Export-ModuleMember -Function Get-PhoenixApplicationManifest, Test-PhoenixApplicationSatisfied, Install-PhoenixWinGetPackage, Install-PhoenixMsiPackage, Install-PhoenixExePackage, Install-PhoenixApplication, Install-PhoenixApplications, Get-PhoenixProfile, Expand-PhoenixProfileApplications, Invoke-PhoenixProfile, Get-InstallerModuleDefinition
