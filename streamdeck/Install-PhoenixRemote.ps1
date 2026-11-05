<#
.SYNOPSIS
    Installs the Phoenix Remote Stream Deck plugin and its ready-made profile.

.DESCRIPTION
    Stops the Stream Deck app, copies com.projectphoenix.remote.sdPlugin into the
    Stream Deck plugins folder, writes (or refreshes) a "Phoenix Remote" profile
    laid out from streamdeck/profile.json, and starts Stream Deck again.

    The Streamlabs token is NOT part of this script. Enter it yourself in any
    Phoenix Remote key's settings (Streamlabs connection → Token).

.PARAMETER SkipProfile
    Install or update the plugin only; leave profiles untouched.

.EXAMPLE
    .\streamdeck\Install-PhoenixRemote.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipProfile
)

$ErrorActionPreference = 'Stop'

$pluginId   = 'com.projectphoenix.remote'
$source     = Join-Path $PSScriptRoot "$pluginId.sdPlugin"
$layoutFile = Join-Path $PSScriptRoot 'profile.json'
$deckRoot   = Join-Path $env:APPDATA 'Elgato\StreamDeck'
$pluginsDir = Join-Path $deckRoot 'Plugins'
$target     = Join-Path $pluginsDir "$pluginId.sdPlugin"
# Fixed profile id so re-running the installer updates the same profile.
$profileId  = '7E0A5C1D-9B4F-4C1E-8F00-50E1A2C3D4F5'
$pageId     = 'A1B2C3D4-0001-4F00-9A00-50E1A2C3D4F5'
$defaultId  = 'A1B2C3D4-0000-4F00-9A00-50E1A2C3D4F5'

function Write-JsonNoBom([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 12 -Compress
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path $source)) { throw "Plugin source not found: $source" }
if (-not (Test-Path $deckRoot)) { throw "Stream Deck app data not found at $deckRoot. Is Stream Deck installed?" }

# --- Stop Stream Deck --------------------------------------------------------
$exe = (Get-Process StreamDeck -ErrorAction SilentlyContinue | Select-Object -First 1).Path
if (-not $exe) { $exe = Join-Path $env:ProgramFiles 'Elgato\StreamDeck\StreamDeck.exe' }
Get-Process StreamDeck -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# --- Plugin ------------------------------------------------------------------
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item $source $target -Recurse
Write-Host "Plugin installed: $target"

# --- Profile -----------------------------------------------------------------
if (-not $SkipProfile) {
    $profilesDir = Join-Path $deckRoot 'ProfilesV3'
    # Borrow the device identity from an existing profile so the new one binds to this Stream Deck.
    $device = Get-ChildItem $profilesDir -Filter manifest.json -Recurse -Depth 1 |
        ForEach-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).Device } |
        Where-Object { $_.UUID } | Select-Object -First 1
    if (-not $device) { throw 'No existing Stream Deck profile found to read the device id from. Open Stream Deck once, then re-run.' }

    $layout  = Get-Content $layoutFile -Raw | ConvertFrom-Json
    $version = (Get-Content (Join-Path $source 'manifest.json') -Raw | ConvertFrom-Json).Version
    $actions = [ordered]@{}
    foreach ($key in $layout.keys) {
        $actions[$key.position] = [ordered]@{
            ActionID    = [guid]::NewGuid().ToString()
            LinkedTitle = $true
            Name        = $key.name
            Plugin      = [ordered]@{ Name = 'Phoenix Remote'; UUID = $pluginId; Version = $version }
            Resources   = $null
            Settings    = $key.settings
            State       = 0
            States      = @(@{})
            UUID        = "$pluginId.$($key.action)"
        }
    }

    $profileDir = Join-Path $profilesDir "$profileId.sdProfile"
    if (Test-Path $profileDir) { Remove-Item $profileDir -Recurse -Force }
    $pageDir    = Join-Path $profileDir "Profiles\$pageId"
    $defaultDir = Join-Path $profileDir "Profiles\$defaultId"
    New-Item -ItemType Directory -Force $pageDir, $defaultDir | Out-Null

    Write-JsonNoBom (Join-Path $profileDir 'manifest.json') ([ordered]@{
        Device  = [ordered]@{ Model = $device.Model; UUID = $device.UUID }
        Name    = $layout.name
        Pages   = [ordered]@{ Current = $pageId.ToLower(); Default = $defaultId.ToLower(); Pages = @($pageId.ToLower()) }
        Version = '3.0'
    })
    Write-JsonNoBom (Join-Path $pageDir 'manifest.json') ([ordered]@{
        Controllers = @([ordered]@{ Actions = $actions; Type = 'Keypad' })
        Icon = ''; Name = ''
    })
    Write-JsonNoBom (Join-Path $defaultDir 'manifest.json') ([ordered]@{
        Controllers = @([ordered]@{ Actions = $null; Type = 'Keypad' })
        Icon = ''; Name = ''
    })
    Write-Host "Profile '$($layout.name)' written: $profileDir"
}

# --- Start Stream Deck -------------------------------------------------------
if (Test-Path $exe) {
    Start-Process $exe
    Write-Host 'Stream Deck restarted.'
} else {
    Write-Warning "Start Stream Deck manually (not found at $exe)."
}
