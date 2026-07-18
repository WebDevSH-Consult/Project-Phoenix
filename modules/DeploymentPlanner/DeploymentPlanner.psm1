<#
    Phoenix Intelligent Deployment Planner (ADR 0016).

    Builds an explainable deployment plan from the machine's actual state and
    the work Phoenix can actually perform - "here is exactly what I will do,
    and why" - without executing anything. The orchestration/brain layer over
    the rest of the pipeline: it reuses the same predicates the executors use
    (Test-PhoenixApplicationSatisfied, Test-PhoenixSettingApplied,
    Get-PhoenixPreflightState, Test-PhoenixElevated), so the plan matches what
    a real run would do.

    Plans only real actions - config/profile-gated application installs and
    Windows settings. It never invents capabilities Phoenix lacks. The plan
    header carries the detected hardware so plans are machine-aware.

    Operator-invoked (not orchestrated). Depends on PhoenixLogging; imports the
    capability modules it consumes itself.
#>

Import-Module (Join-Path $PSScriptRoot '..\PhoenixCore\PhoenixCore.psd1')
Import-Module (Join-Path $PSScriptRoot '..\PhoenixConfig\PhoenixConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\HardwareDetection\HardwareDetection.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Validation\Validation.psd1')
Import-Module (Join-Path $PSScriptRoot '..\PhoenixBootstrap\PhoenixBootstrap.psd1')
Import-Module (Join-Path $PSScriptRoot '..\WindowsConfig\WindowsConfig.psd1')
Import-Module (Join-Path $PSScriptRoot '..\Installer\Installer.psd1')

# Coarse, declared estimate heuristics (ADR 0016) - placeholders, not measurements.
$script:EstimateInstallSeconds = 120
$script:EstimateApplySeconds = 5

function New-PhoenixDeploymentPlan {
    <#
        .SYNOPSIS
        Builds a deployment plan: for the applications and settings in scope,
        decides the action (Install/Apply/Skip/Defer) and why - without
        changing anything.

        .DESCRIPTION
        Applications are selected by -ProfileName (expanded with dependencies)
        or, without it, by configuration (ConfigFlag). Settings are always
        selected by configuration. Uses the same predicates the executors use,
        so the plan reflects what a real run would do. See ADR 0016.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ProfileName
    )

    $configuration = Get-PhoenixConfiguration -RootPath $RootPath
    $hardware = Get-PhoenixHardware
    $elevated = Test-PhoenixElevated
    $preflight = Get-PhoenixPreflightState

    $appManifests = @(Get-PhoenixApplicationManifest -ManifestsPath (Join-Path $RootPath 'modules\Installer\Applications'))
    $settingManifests = @(Get-PhoenixSettingManifest -ManifestsPath (Join-Path $RootPath 'modules\WindowsConfig\Settings'))

    # Application scope: profile selection (with dependencies) or config gating.
    if ($ProfileName) {
        $workstationProfile = Get-PhoenixProfile -ProfilesPath (Join-Path $RootPath 'profiles') -ProfileName $ProfileName
        $scopedApps = @(Expand-PhoenixProfileApplications -Manifests $appManifests -ApplicationNames $workstationProfile.Applications)
        $scopeLabel = "Profile: $($workstationProfile.Name)"
    }
    else {
        $scopedApps = @($appManifests | Where-Object { Get-PhoenixConfigValue -Configuration $configuration -Path $_.ConfigFlag })
        $scopeLabel = 'Configuration'
    }

    $scopedSettings = @($settingManifests | Where-Object { Get-PhoenixConfigValue -Configuration $configuration -Path $_.ConfigFlag })

    $preflightReason = ($preflight.Results | Where-Object Status -eq 'FAIL' | ForEach-Object { $_.Name }) -join ', '

    $actions = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($manifest in $scopedSettings) {
        if (Test-PhoenixSettingApplied -Manifest $manifest) {
            $actions.Add([PSCustomObject]@{ Category = 'Setting'; Name = $manifest.Name; Action = 'Skip'; Reason = 'Already in the desired state.'; Risk = 'Low'; EstimatedSeconds = 0 })
        }
        elseif ($manifest.RequiresElevation -and -not $elevated) {
            $actions.Add([PSCustomObject]@{ Category = 'Setting'; Name = $manifest.Name; Action = 'Defer'; Reason = 'Requires elevation - re-run elevated to apply.'; Risk = 'Medium'; EstimatedSeconds = 0 })
        }
        else {
            $risk = if ($manifest.RequiresElevation) { 'Medium' } else { 'Low' }
            $actions.Add([PSCustomObject]@{ Category = 'Setting'; Name = $manifest.Name; Action = 'Apply'; Reason = 'Not in the desired state.'; Risk = $risk; EstimatedSeconds = $script:EstimateApplySeconds })
        }
    }

    foreach ($manifest in $scopedApps) {
        if (Test-PhoenixApplicationSatisfied -Manifest $manifest) {
            $actions.Add([PSCustomObject]@{ Category = 'Application'; Name = $manifest.Name; Action = 'Skip'; Reason = 'Already installed.'; Risk = 'Low'; EstimatedSeconds = 0 })
        }
        elseif (-not $preflight.Safe) {
            $actions.Add([PSCustomObject]@{ Category = 'Application'; Name = $manifest.Name; Action = 'Defer'; Reason = "System not in a safe state for installation ($preflightReason)."; Risk = 'Low'; EstimatedSeconds = 0 })
        }
        else {
            $actions.Add([PSCustomObject]@{ Category = 'Application'; Name = $manifest.Name; Action = 'Install'; Reason = 'Not installed.'; Risk = 'Low'; EstimatedSeconds = $script:EstimateInstallSeconds })
        }
    }

    $actionArray = $actions.ToArray()
    $changing = @($actionArray | Where-Object Action -in @('Install', 'Apply'))
    $totalSeconds = ($actionArray | Measure-Object -Property EstimatedSeconds -Sum).Sum
    $overallRisk = if ($actionArray | Where-Object Risk -eq 'Medium') { 'Medium' } else { 'Low' }

    return [PSCustomObject]@{
        Timestamp     = (Get-Date).ToString('o')
        Machine       = [PSCustomObject]@{
            ComputerName = [System.Environment]::MachineName
            FormFactor   = $hardware.System.FormFactor
            Cpu          = "$($hardware.Cpu.Name) [$($hardware.Cpu.Vendor)]"
            Gpus         = @($hardware.Gpus | ForEach-Object { "$($_.Name) [$($_.Vendor)]" })
            MemoryGB     = $hardware.MemoryGB
        }
        Scope         = $scopeLabel
        Elevated      = $elevated
        PreflightSafe = $preflight.Safe
        Actions       = $actionArray
        Summary       = [PSCustomObject]@{
            Install         = @($actionArray | Where-Object Action -eq 'Install').Count
            Apply           = @($actionArray | Where-Object Action -eq 'Apply').Count
            Skip            = @($actionArray | Where-Object Action -eq 'Skip').Count
            Defer           = @($actionArray | Where-Object Action -eq 'Defer').Count
            Changing        = $changing.Count
            EstimatedMinutes = [math]::Round($totalSeconds / 60, 1)
            Risk            = $overallRisk
        }
    }
}

function Show-PhoenixDeploymentPlan {
    <#
        .SYNOPSIS
        Renders a deployment plan to the console for review before execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Plan
    )

    Write-Host ''
    Write-Host "Phoenix Deployment Plan - $($Plan.Scope)" -ForegroundColor Cyan
    Write-Host "  Machine: $($Plan.Machine.ComputerName) ($($Plan.Machine.FormFactor)), $($Plan.Machine.Cpu), $($Plan.Machine.MemoryGB) GB"
    Write-Host "  GPU:     $($Plan.Machine.Gpus -join '; ')"
    Write-Host "  Elevated: $($Plan.Elevated)    Preflight safe: $($Plan.PreflightSafe)"
    Write-Host ''

    $glyphs = @{ Install = '+'; Apply = '~'; Skip = 'o'; Defer = '!' }
    foreach ($action in $Plan.Actions) {
        $glyph = if ($glyphs.ContainsKey($action.Action)) { $glyphs[$action.Action] } else { '-' }
        $colour = switch ($action.Action) { 'Install' { 'Green' } 'Apply' { 'Green' } 'Defer' { 'Yellow' } default { 'Gray' } }
        Write-Host ("  [{0}] {1,-11} {2,-32} {3}" -f $glyph, $action.Action, $action.Name, $action.Reason) -ForegroundColor $colour
    }

    Write-Host ''
    $s = $Plan.Summary
    Write-Host "  $($s.Changing) change(s): $($s.Install) install, $($s.Apply) apply | $($s.Skip) skip, $($s.Defer) deferred"
    Write-Host "  Estimated time: ~$($s.EstimatedMinutes)m (rough)    Risk: $($s.Risk)" -ForegroundColor $(if ($s.Risk -eq 'Medium') { 'Yellow' } else { 'Green' })
    Write-Host ''
}

function Export-PhoenixDeploymentPlan {
    <#
        .SYNOPSIS
        Persists a deployment plan as timestamped JSON under plans/ - the
        auditable, exportable artifact.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Plan,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$PlansPath = (Join-Path $RootPath 'plans')
    )

    if (-not (Test-Path -LiteralPath $PlansPath)) {
        New-Item -ItemType Directory -Path $PlansPath -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $PlansPath "deployment-plan-$stamp.json"
    $Plan | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8

    Write-PhoenixLog -Level SUCCESS -Message "[Planner] Deployment plan exported: $path"
    return $path
}

function Get-PhoenixDeploymentPlan {
    <#
        .SYNOPSIS
        Loads the most recent exported deployment plan (or -Path).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$Path
    )

    if (-not $Path) {
        $plansDir = Join-Path $RootPath 'plans'
        $latest = Get-ChildItem -LiteralPath $plansDir -Filter 'deployment-plan-*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if (-not $latest) {
            Write-PhoenixLog -Level ERROR -Message "[Planner] No deployment plan found under $plansDir."
            throw "No deployment plan found under $plansDir."
        }
        $Path = $latest.FullName
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

Export-ModuleMember -Function New-PhoenixDeploymentPlan, Show-PhoenixDeploymentPlan, Export-PhoenixDeploymentPlan, Get-PhoenixDeploymentPlan
