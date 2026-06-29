<#
    Phoenix Configuration Engine.

    Loads phoenix.json and every per-domain configuration file it references
    (configs/windows.json, applications.json, gaming.json, ai.json,
    powershell.json) into a single merged configuration object. Nothing is
    hard-coded: Bootstrap.ps1 and every module read configuration through
    Get-PhoenixConfiguration rather than parsing JSON themselves.

    Depends on PhoenixLogging being imported first (for Write-PhoenixLog).
#>

function Read-PhoenixJsonFile {
    <#
        .SYNOPSIS
        Reads and parses a single JSON file, failing cleanly (logged + a clear
        exception) rather than letting a raw .NET error leak to the caller.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-PhoenixLog -Level ERROR -Message "Configuration file not found: $Description ($Path)"
        throw "Configuration file not found: $Description ($Path)"
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        Write-PhoenixLog -Level ERROR -Message "Failed to parse $Description ($Path): $($_.Exception.Message)"
        throw "Failed to parse $Description ($Path): $($_.Exception.Message)"
    }
}

function Get-PhoenixConfiguration {
    <#
        .SYNOPSIS
        Loads phoenix.json and every per-domain configuration file it
        references, returning a single merged configuration object.

        .DESCRIPTION
        phoenix.json's "modules" section maps a domain name (e.g. "windows")
        to a path, relative to RootPath, of that domain's configuration file.
        Each referenced file is loaded and attached to the returned object
        under that domain name. The root phoenix.json's own top-level
        properties (version, name, logging, ...) are also attached directly.

        .PARAMETER RootPath
        The Project Phoenix repository root - the directory containing
        phoenix.json.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $phoenixJsonPath = Join-Path $RootPath 'phoenix.json'
    $root = Read-PhoenixJsonFile -Path $phoenixJsonPath -Description 'phoenix.json'

    $config = [ordered]@{}
    foreach ($property in $root.PSObject.Properties) {
        if ($property.Name -ne 'modules') {
            $config[$property.Name] = $property.Value
        }
    }

    $domains = [ordered]@{}
    if ($root.PSObject.Properties.Name -contains 'modules') {
        foreach ($domain in $root.modules.PSObject.Properties) {
            $domainPath = Join-Path $RootPath $domain.Value
            $domains[$domain.Name] = Read-PhoenixJsonFile -Path $domainPath -Description "$($domain.Name) configuration"
        }
    }
    $config['Modules'] = [PSCustomObject]$domains

    return [PSCustomObject]$config
}

Export-ModuleMember -Function Get-PhoenixConfiguration
