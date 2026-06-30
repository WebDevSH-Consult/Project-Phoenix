<#
    Phoenix Bootstrap Engine - turns Bootstrap.ps1 from a script that hard-codes
    which modules to run into an orchestrator that discovers them.

    Pipeline: discover module manifests -> validate them -> resolve dependency
    order -> import each module and collect its lifecycle definition -> hand
    the whole batch to Invoke-PhoenixBootstrap (from PhoenixCore) for execution,
    logging, and the aggregate health report.

    Every orchestrated module is a folder under modules/ containing a
    module.json manifest (see Get-PhoenixModuleManifest) plus a PowerShell
    module of the same name. Engine modules (PhoenixCore, PhoenixLogging,
    PhoenixConfig, PhoenixBootstrap itself) are infrastructure imported
    directly by Bootstrap.ps1 and do not carry a module.json - they are not
    orchestrated.

    Depends on PhoenixLogging and PhoenixCore being imported first.
#>

function Get-PhoenixModuleManifest {
    <#
        .SYNOPSIS
        Discovers and validates every module.json manifest under ModulesPath.

        .DESCRIPTION
        Each subfolder of ModulesPath containing a module.json is treated as
        an orchestrated module. A manifest requires Name, Version, RunOrder,
        Enabled, and EntryPoint (the function name that returns the module's
        lifecycle definition); Dependencies is optional and defaults to an
        empty list. The module's PowerShell module file is expected at
        <folder>/<folder>.psd1. Folders without a module.json are skipped.

        .PARAMETER ModulesPath
        The directory containing one subfolder per module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ModulesPath
    )

    $manifests = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenNames = @{}

    $moduleDirs = Get-ChildItem -LiteralPath $ModulesPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $moduleDirs) {
        $manifestPath = Join-Path $dir.FullName 'module.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            $raw = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-PhoenixLog -Level ERROR -Message "Failed to parse module manifest for '$($dir.Name)' ($manifestPath): $($_.Exception.Message)"
            throw "Failed to parse module manifest for '$($dir.Name)' ($manifestPath): $($_.Exception.Message)"
        }

        foreach ($field in @('Name', 'Version', 'RunOrder', 'Enabled', 'EntryPoint')) {
            if ($raw.PSObject.Properties.Name -notcontains $field) {
                Write-PhoenixLog -Level ERROR -Message "Module manifest for '$($dir.Name)' is missing required field '$field' ($manifestPath)"
                throw "Module manifest for '$($dir.Name)' is missing required field '$field' ($manifestPath)"
            }
        }

        $dependencies = @()
        if ($raw.PSObject.Properties.Name -contains 'Dependencies' -and $null -ne $raw.Dependencies) {
            $dependencies = @($raw.Dependencies)
        }

        $manifest = [PSCustomObject]@{
            Name         = [string]$raw.Name
            Version      = [string]$raw.Version
            Dependencies = $dependencies
            RunOrder     = [int]$raw.RunOrder
            Enabled      = [bool]$raw.Enabled
            EntryPoint   = [string]$raw.EntryPoint
            ModulePath   = Join-Path $dir.FullName "$($dir.Name).psd1"
            FolderName   = $dir.Name
        }

        if ($seenNames.ContainsKey($manifest.Name)) {
            Write-PhoenixLog -Level ERROR -Message "Duplicate module name '$($manifest.Name)' found in '$($dir.Name)' and '$($seenNames[$manifest.Name])'"
            throw "Duplicate module name '$($manifest.Name)' found in '$($dir.Name)' and '$($seenNames[$manifest.Name])'"
        }
        $seenNames[$manifest.Name] = $dir.Name

        if (-not (Test-Path -LiteralPath $manifest.ModulePath)) {
            Write-PhoenixLog -Level ERROR -Message "Module '$($manifest.Name)' has no module file at $($manifest.ModulePath)"
            throw "Module '$($manifest.Name)' has no module file at $($manifest.ModulePath)"
        }

        $manifests.Add($manifest)
    }

    return $manifests.ToArray()
}

function Resolve-PhoenixModuleOrder {
    <#
        .SYNOPSIS
        Topologically sorts modules by their declared dependencies, breaking
        ties with RunOrder then Name for a deterministic result.

        .DESCRIPTION
        Every dependency must reference another manifest in the same set
        (typically the enabled subset) or this throws. A dependency cycle
        also throws, naming the modules involved.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Manifests
    )

    $byName = @{}
    foreach ($manifest in $Manifests) { $byName[$manifest.Name] = $manifest }

    foreach ($manifest in $Manifests) {
        foreach ($dependency in $manifest.Dependencies) {
            if (-not $byName.ContainsKey($dependency)) {
                Write-PhoenixLog -Level ERROR -Message "Module '$($manifest.Name)' depends on '$dependency', which is not an enabled module."
                throw "Module '$($manifest.Name)' depends on '$dependency', which is not an enabled module."
            }
        }
    }

    $resolved = [System.Collections.Generic.List[PSCustomObject]]::new()
    $resolvedNames = [System.Collections.Generic.HashSet[string]]::new()
    $remaining = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($manifest in $Manifests) { $remaining.Add($manifest) }

    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $manifest = $_
            $unresolvedDependency = $manifest.Dependencies | Where-Object { -not $resolvedNames.Contains($_) }
            return -not $unresolvedDependency
        })

        if ($ready.Count -eq 0) {
            $stuckNames = ($remaining | ForEach-Object { $_.Name }) -join ', '
            Write-PhoenixLog -Level ERROR -Message "Circular dependency detected among modules: $stuckNames"
            throw "Circular dependency detected among modules: $stuckNames"
        }

        foreach ($manifest in ($ready | Sort-Object RunOrder, Name)) {
            $resolved.Add($manifest)
            $null = $resolvedNames.Add($manifest.Name)
            $remaining.Remove($manifest) | Out-Null
        }
    }

    return $resolved.ToArray()
}

function Invoke-PhoenixOrchestration {
    <#
        .SYNOPSIS
        Discovers, validates, orders, and executes every enabled module under
        ModulesPath, returning the aggregate health report.

        .DESCRIPTION
        Runs the full Bootstrap Engine pipeline: discover module manifests,
        validate them, resolve dependency/run order, import each module and
        call its declared EntryPoint to get its lifecycle definition, then
        hand the batch to Invoke-PhoenixBootstrap for execution and reporting.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ModulesPath = (Join-Path $RootPath 'modules')
    )

    Write-PhoenixLog -Level INFO -Message 'Discovering modules...'
    $manifests = Get-PhoenixModuleManifest -ModulesPath $ModulesPath

    $enabled = @($manifests | Where-Object Enabled)
    Write-PhoenixLog -Level INFO -Message "Discovered $($manifests.Count) module manifest(s); $($enabled.Count) enabled."

    Write-PhoenixLog -Level INFO -Message 'Resolving module dependencies and execution order...'
    $ordered = Resolve-PhoenixModuleOrder -Manifests $enabled

    $definitions = @(
        foreach ($manifest in $ordered) {
            Write-PhoenixLog -Level INFO -Message "Loading module '$($manifest.Name)' from $($manifest.ModulePath)..."
            Import-Module $manifest.ModulePath -Force

            $command = Get-Command -Name $manifest.EntryPoint -ErrorAction SilentlyContinue
            if (-not $command) {
                Write-PhoenixLog -Level ERROR -Message "Module '$($manifest.Name)' declares EntryPoint '$($manifest.EntryPoint)', which was not found after import."
                throw "Module '$($manifest.Name)' declares EntryPoint '$($manifest.EntryPoint)', which was not found after import."
            }

            & $command
        }
    )

    return Invoke-PhoenixBootstrap -Modules $definitions
}

Export-ModuleMember -Function Get-PhoenixModuleManifest, Resolve-PhoenixModuleOrder, Invoke-PhoenixOrchestration
