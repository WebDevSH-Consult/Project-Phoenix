# PhoenixConfig

The configuration engine. Loads `phoenix.json` and every per-domain configuration file it references, returning one merged object — nothing in Phoenix parses JSON directly outside this module.

## Usage

```powershell
Import-Module ./PhoenixLogging.psd1
Import-Module ./PhoenixConfig.psd1
Initialize-PhoenixLog -LogDirectory ./logs

$config = Get-PhoenixConfiguration -RootPath $PSScriptRoot
$config.version          # from phoenix.json's top-level fields
$config.Modules.windows  # from configs/windows.json
```

## Contract

`phoenix.json`'s `modules` section maps a domain name to a path (relative to `RootPath`) of that domain's config file:

```json
{
  "modules": {
    "windows": "configs/windows.json"
  }
}
```

`Get-PhoenixConfiguration` resolves and loads each one, attaching it to the returned object's `Modules` property under that domain name. All other top-level `phoenix.json` properties (`version`, `name`, `logging`, ...) are attached directly to the returned object.

## Failure behaviour

A missing or malformed file (the root `phoenix.json` or any referenced domain file) does not throw a raw exception. It is logged via `Write-PhoenixLog -Level ERROR` naming the file and the problem, then a clean `[string]`-message exception is thrown so the caller's `try`/`catch` (see `Bootstrap.ps1`) can handle it without a stack trace leaking to the user.
