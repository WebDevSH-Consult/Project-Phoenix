# PhoenixLogging

Structured logging engine. Every Phoenix module logs through this module rather than `Write-Host` directly, so output is consistent, leveled, and persisted.

## Usage

```powershell
Import-Module ./PhoenixLogging.psd1
Initialize-PhoenixLog -LogDirectory ./logs
Write-PhoenixLog -Level INFO -Message 'Installing Git...'
Write-PhoenixLog -Level SUCCESS -Message 'Git 2.52 installed' -Duration 18.2
```

Output:

```
[09:14:21] INFO    Installing Git...
[09:14:39] SUCCESS Git 2.52 installed (Duration: 18.2s)
```

`Initialize-PhoenixLog` must be called once per run before any `Write-PhoenixLog` call; it creates a timestamped log file under the given directory. See [ADR 0005](../../docs/adr/0005-logging.md) for why this format was chosen over free-text console output.
