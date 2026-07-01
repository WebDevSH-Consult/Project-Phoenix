# Contributing to Project Phoenix

Project Phoenix is developed with the same discipline as a commercial product, even though it started as a personal workstation platform.

## Branch Strategy

- **`main`** — protected. Only stable, tagged releases land here.
- **`develop`** — default development branch. All finished feature work merges here first.
- **`feature/<name>`** — one branch per feature, branched from `develop`.
  - `feature/bootstrap-core`
  - `feature/windows-config`
  - `feature/app-installer`
  - `feature/gaming-suite`
  - `feature/health-dashboard`
  - `feature/ai-command-centre`
- **`bugfix/<name>`** — bug fixes, branched from `develop`.
- **`docs/<name>`** — documentation-only changes.
- **`experiment/<name>`** — throwaway exploration, never merged directly.

## Pull Requests

Every change is reviewed before merging — no direct pushes to `main` or `develop`.

A PR must:

- Have a clear purpose (link an issue where applicable).
- Pass all CI checks (PowerShell syntax, JSON validation, Markdown link validation, module tests, bootstrap integrity).
- Include documentation updates if behaviour changed.
- Include logging for any new user-facing action.
- Include a version bump if the change is user-facing.
- Fit the architecture described in [ARCHITECTURE.md](./ARCHITECTURE.md).

## Commit Discipline

Nothing gets committed unless it passes validation, has documentation, has logging where appropriate, has a version number if user-facing, and fits the architecture. If it doesn't meet all five, it isn't ready.

## Architectural Decisions

If you're making a decision that future-you (or a contributor) will ask "why did we do it this way?" about, write an ADR in `docs/adr/` using the existing numbering convention. Keep it short: what we decided, why, what alternatives were considered.

## Module Standards

Every module implements the lifecycle defined in [ARCHITECTURE.md](./ARCHITECTURE.md): Initialise → Validate → Execute → Verify → Log → Report. No exceptions, no shortcuts.

## Validation First

Phoenix is not merely an installer. Every installation step must have a corresponding validation step.

Every validation check should:

- Return **PASS**, **WARN**, or **FAIL** — never a bare boolean or a silent skip.
- Provide diagnostic information (what was checked, what was found).
- Attempt automatic repair when the fix is safe, well-understood, and reversible — prefer self-healing over documentation of a manual workaround.
- Log every result via `Write-PhoenixLog`.
- **Never assume a specific hardware vendor.** Detect first (see `Test-PhoenixGpu` in `modules/Validation`), decide second. Support AMD, NVIDIA, and Intel; an unrecognised result is `WARN`, not a guess.
- **Never assume a Microsoft Store package exists.** Its absence is `WARN`, not `FAIL` — not every workstation profile expects every package.
- Have Pester coverage that mocks whatever OS/hardware API it calls, so CI passes deterministically regardless of the runner's actual hardware.

Deployment and validation logic should be data-driven (detected at runtime, read from configuration) rather than hard-coded to one hardware or software configuration. See [EPIC-04](./docs/roadmap/EPIC-04-System-Validation.md) for the System Validation & Self-Healing epic this standard supports.
