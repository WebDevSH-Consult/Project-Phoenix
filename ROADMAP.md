# Roadmap

Project Phoenix follows semantic versioning. Each milestone below represents a meaningful, working increment — not just "some scripts got written."

**Capability milestones vs. release tags.** The numbered milestones below track *capabilities*; they do not map one-to-one onto release tags. Releases bundle several milestones — see [Released](#released) for the actual tag → capability mapping and [CHANGELOG.md](./CHANGELOG.md) for the detail.

| Milestone | Capability                              | Status |
|-----------|-----------------------------------------|--------|
| 0.1       | Repository Foundation                   | ✅ Done |
| 0.2       | Phoenix Core                            | ✅ Done |
| 0.3       | Logging Engine                          | ✅ Done |
| 0.4       | Configuration Engine                    | ✅ Done |
| 0.5       | Bootstrap Engine                        | ✅ Done |
| 0.6       | Application Deployment Engine           | ✅ Done |
| 0.7       | Workstation Profiles                    | ✅ Done |
| 0.8       | Windows Configuration                   | ✅ Done |
| 0.9       | Health Dashboard                        | ✅ Done |
| —         | **Configuration management** — Deployment Planner, transactional rollback, drift detection & repair (beyond the original numbered plan; shipped in v0.9.0) | ✅ Done |
| 1.0       | Fully Unattended Workstation Rebuild    | ◻ In progress |

The former "Gaming Suite" milestone is absorbed: gaming applications are now manifests (`modules/Installer/Applications/`) selected by the `Gaming` profile (`profiles/gaming.json`) — no dedicated suite needed.

## Released

| Tag | Title | Capabilities |
|-----|-------|--------------|
| [v0.2.0](https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.2.0) | Repository Foundation + Phoenix Core | Milestones 0.1–0.3 (foundation, core, logging) |
| [v0.7.0](https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.7.0) | Application Deployment Platform | Milestones 0.4–0.7 (configuration, bootstrap engine, installer, profiles) + first System Validation slice |
| [v0.8.0](https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.8.0) | Configuration, Reporting & Hardening | Milestones 0.8–0.9 (Windows Configuration, Health Dashboard) + Hardware Detection, Installer Preflight gate, Elevation strategy |
| [v0.9.0](https://github.com/WebDevSH-Consult/Project-Phoenix/releases/tag/v0.9.0) | Planning, Recovery & Configuration Management | Deployment Planner, Recovery/rollback + transactional runs, State Engine (drift detection & repair), installer completeness |

## Beyond 1.0

- Self-Healing Engine (scheduled drift detection and remediation — extends [EPIC-04](./docs/roadmap/EPIC-04-System-Validation.md))
- Cloud sync & configuration export
- AI Command Centre (local + cloud AI tooling orchestration)
- Backup & recovery manager
- Community contribution support (if opened up beyond personal use)

## Working Agreement

Nothing ships in a release unless it:

1. Passes CI validation (PowerShell syntax, JSON schema, Markdown links, module tests).
2. Has documentation.
3. Has logging where appropriate.
4. Has a version number if user-facing.
5. Fits the architecture defined in [ARCHITECTURE.md](./ARCHITECTURE.md).

See [CHANGELOG.md](./CHANGELOG.md) for what has actually shipped.
