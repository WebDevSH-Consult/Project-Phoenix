# PhoenixBootstrap

The Bootstrap Engine. Turns `Bootstrap.ps1` from a script that hard-codes which modules to run into an orchestrator that discovers them — `Bootstrap.ps1` doesn't need to know Steam, Epic, or PowerToys modules exist; it just calls `Invoke-PhoenixOrchestration`.

## Pipeline

```
Discover module manifests
        ↓
Validate manifests
        ↓
Resolve dependencies / execution order
        ↓
Import each module, collect its lifecycle definition
        ↓
Execute via Invoke-PhoenixBootstrap (PhoenixCore)
        ↓
Log + aggregate health report
```

## The module manifest (`module.json`)

Every orchestrated module is a folder under `modules/` containing a `module.json`:

```json
{
  "Name": "Example",
  "Version": "0.1.0",
  "Dependencies": [],
  "RunOrder": 10,
  "Enabled": true,
  "EntryPoint": "Get-ExampleModuleDefinition"
}
```

| Field | Required | Meaning |
|---|---|---|
| `Name` | yes | Unique identifier used for dependency references and ordering output. |
| `Version` | yes | The module's own version (informational). |
| `Dependencies` | no (default `[]`) | Names of other modules that must run first. |
| `RunOrder` | yes | Tiebreaker when modules have no dependency relationship to each other. |
| `Enabled` | yes | Disabled modules are discovered but excluded from execution. |
| `EntryPoint` | yes | The function (exported by the module's `.psd1`) that returns its [lifecycle definition](../PhoenixCore/README.md#module-contract). |

The module's PowerShell module is expected at `<folder>/<folder>.psd1` — the same convention every existing module already follows.

**Engine modules don't get a manifest.** `PhoenixCore`, `PhoenixLogging`, `PhoenixConfig`, and `PhoenixBootstrap` itself are infrastructure, imported directly by `Bootstrap.ps1`. Only workstation-automation modules (Example today; Steam, Epic, Windows, AI tooling, etc. as they're built) carry a `module.json` and go through orchestration.

## Adding a new module

1. Create `modules/<Name>/` with `<Name>.psm1`, `<Name>.psd1`, and `module.json`.
2. Implement a function matching `EntryPoint` that returns a lifecycle definition hashtable (see [PhoenixCore](../PhoenixCore/README.md)).
3. That's it — `Bootstrap.ps1` requires no changes.

## Failure behaviour

A malformed or incomplete manifest, a missing dependency, a dependency cycle, or a missing `EntryPoint` function all fail loudly: logged via `Write-PhoenixLog -Level ERROR` naming the module and the problem, then a clean exception — never a silent skip or a raw stack trace.
