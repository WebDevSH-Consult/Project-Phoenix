<#
    Phoenix Windows Configuration Engine (Roadmap 0.8 / ADR 0009).

    Every Windows setting is data (a JSON manifest under Settings/), not a
    bespoke script - mirroring the Application Deployment Engine's design.
    The first supported mechanism is Registry (HKCU), safe to apply without
    elevation. See modules/WindowsConfig/README.md and
    docs/adr/0009-windows-configuration-engine.md.

    Depends on PhoenixLogging being imported first; imports PhoenixConfig
    itself for configuration-flag gating.
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')

#region Registry provider - thin, mockable wrappers around the real registry

function Get-PhoenixRegistryValue {
    <#
        .SYNOPSIS
        Reads a single registry value, returning $null if the key or value
        does not exist. Thin and mockable - tests never touch the registry.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ValueName
    )

    try {
        $item = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction Stop
        return $item.$ValueName
    }
    catch {
        return $null
    }
}

function Set-PhoenixRegistryValue {
    <#
        .SYNOPSIS
        Writes a single registry value, creating the key if needed. Thin and
        mockable - tests never touch the registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ValueName,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$ValueKind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $ValueName -Value $Value -PropertyType $ValueKind -Force | Out-Null
}

#endregion

#region Setting manifest discovery

function Get-PhoenixSettingManifest {
    <#
        .SYNOPSIS
        Discovers and validates every setting manifest under ManifestsPath.

        .DESCRIPTION
        Required fields for every manifest: Name, Type, ConfigFlag. The
        Registry type additionally requires Path, ValueName, DesiredValue,
        and ValueKind. An unknown Type fails at discovery - never silently
        skipped.
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
            Write-PhoenixLog -Level ERROR -Message "Failed to parse setting manifest '$($file.Name)': $($_.Exception.Message)"
            throw "Failed to parse setting manifest '$($file.Name)': $($_.Exception.Message)"
        }

        foreach ($field in @('Name', 'Type', 'ConfigFlag')) {
            if ($raw.PSObject.Properties.Name -notcontains $field) {
                Write-PhoenixLog -Level ERROR -Message "Setting manifest '$($file.Name)' is missing required field '$field'."
                throw "Setting manifest '$($file.Name)' is missing required field '$field'."
            }
        }

        if ($raw.Type -ne 'Registry') {
            Write-PhoenixLog -Level ERROR -Message "Setting manifest '$($file.Name)' has an unknown Type '$($raw.Type)'."
            throw "Setting manifest '$($file.Name)' has an unknown Type '$($raw.Type)'."
        }

        foreach ($field in @('Path', 'ValueName', 'DesiredValue', 'ValueKind')) {
            if ($raw.PSObject.Properties.Name -notcontains $field) {
                Write-PhoenixLog -Level ERROR -Message "Registry setting manifest '$($file.Name)' is missing required field '$field'."
                throw "Registry setting manifest '$($file.Name)' is missing required field '$field'."
            }
        }

        if ($seenNames.ContainsKey($raw.Name)) {
            Write-PhoenixLog -Level ERROR -Message "Duplicate setting name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
            throw "Duplicate setting name '$($raw.Name)' found in '$($file.Name)' and '$($seenNames[$raw.Name])'."
        }
        $seenNames[$raw.Name] = $file.Name

        $manifests.Add([PSCustomObject]@{
            Name         = [string]$raw.Name
            Type         = [string]$raw.Type
            ConfigFlag   = [string]$raw.ConfigFlag
            Path         = [string]$raw.Path
            ValueName    = [string]$raw.ValueName
            DesiredValue = $raw.DesiredValue
            ValueKind    = [string]$raw.ValueKind
        })
    }

    return $manifests.ToArray()
}

#endregion

#region Apply + verify

function Test-PhoenixSettingApplied {
    <#
        .SYNOPSIS
        Checks whether a setting's current state already matches its
        manifest's desired state.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $current = Get-PhoenixRegistryValue -Path $Manifest.Path -ValueName $Manifest.ValueName
    return ($null -ne $current -and "$current" -eq "$($Manifest.DesiredValue)")
}

function Set-PhoenixSetting {
    <#
        .SYNOPSIS
        Applies a single setting: skip if already in the desired state,
        otherwise apply, logging the previous value (rollback data), then
        re-read to verify.

        .DESCRIPTION
        Returns a result in the same {Category, Name, Status, Message} shape
        used throughout Phoenix, plus a PreviousValue property recording
        what the value was before the change (or $null if unset).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $previous = Get-PhoenixRegistryValue -Path $Manifest.Path -ValueName $Manifest.ValueName

    if ($null -ne $previous -and "$previous" -eq "$($Manifest.DesiredValue)") {
        Write-PhoenixLog -Level SUCCESS -Message "[WindowsConfig] $($Manifest.Name): already in desired state."
        return [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'PASS'; Message = 'Already in desired state - no action taken.'; PreviousValue = $previous }
    }

    $previousDisplay = if ($null -eq $previous) { '(unset)' } else { $previous }
    Write-PhoenixLog -Level INFO -Message "[WindowsConfig] $($Manifest.Name): applying $($Manifest.ValueName)=$($Manifest.DesiredValue) at $($Manifest.Path) (previous value: $previousDisplay)."

    try {
        Set-PhoenixRegistryValue -Path $Manifest.Path -ValueName $Manifest.ValueName -Value $Manifest.DesiredValue -ValueKind $Manifest.ValueKind
    }
    catch {
        Write-PhoenixLog -Level ERROR -Message "[WindowsConfig] $($Manifest.Name): failed to apply - $($_.Exception.Message)"
        return [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'FAIL'; Message = "Failed to apply: $($_.Exception.Message)"; PreviousValue = $previous }
    }

    if (Test-PhoenixSettingApplied -Manifest $Manifest) {
        Write-PhoenixLog -Level SUCCESS -Message "[WindowsConfig] $($Manifest.Name): applied and verified."
        return [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'PASS'; Message = "Applied (previous value: $previousDisplay)."; PreviousValue = $previous }
    }

    Write-PhoenixLog -Level ERROR -Message "[WindowsConfig] $($Manifest.Name): applied but post-apply verification did not confirm the desired state."
    return [PSCustomObject]@{ Category = 'Setting'; Name = $Manifest.Name; Status = 'FAIL'; Message = 'Applied but post-apply verification failed.'; PreviousValue = $previous }
}

function Set-PhoenixSettings {
    <#
        .SYNOPSIS
        Applies every setting manifest enabled by configuration.
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
    Write-PhoenixLog -Level INFO -Message "[WindowsConfig] $($Manifests.Count) setting manifest(s) discovered; $($enabled.Count) enabled by configuration."

    return @(
        foreach ($manifest in $enabled) {
            Set-PhoenixSetting -Manifest $manifest
        }
    )
}

#endregion

#region Bootstrap Engine integration

function Get-WindowsConfigModuleDefinition {
    <#
        .SYNOPSIS
        Returns the module definition hashtable consumed by
        Invoke-PhoenixModuleLifecycle, orchestrated via the Bootstrap Engine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name       = 'WindowsConfig'
        Initialize = { Write-PhoenixLog -Level INFO -Message '[WindowsConfig] Preparing Windows configuration engine.' }
        Validate   = { $true }
        Execute    = {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
            $configuration = Get-PhoenixConfiguration -RootPath $repoRoot
            $manifests = Get-PhoenixSettingManifest -ManifestsPath (Join-Path $PSScriptRoot 'Settings')

            $script:PhoenixSettingResults = Set-PhoenixSettings -Manifests $manifests -Configuration $configuration
        }
        Verify     = {
            -not (@($script:PhoenixSettingResults) | Where-Object Status -eq 'FAIL')
        }
    }
}

#endregion

Export-ModuleMember -Function Get-PhoenixRegistryValue, Set-PhoenixRegistryValue, Get-PhoenixSettingManifest, Test-PhoenixSettingApplied, Set-PhoenixSetting, Set-PhoenixSettings, Get-WindowsConfigModuleDefinition
