# Roadmap

Project Phoenix follows semantic versioning. Each milestone below represents a meaningful, working increment — not just "some scripts got written."

| Version | Milestone                              |
|---------|-----------------------------------------|
| 0.1     | Repository Foundation                   |
| 0.2     | Phoenix Core                            |
| 0.3     | Logging Engine                          |
| 0.4     | Configuration Engine                    |
| 0.5     | Bootstrap Engine                        |
| 0.6     | Application Deployment Engine            |
| 0.7     | Workstation Profiles                    |
| 0.8     | Windows Configuration                   |
| 0.9     | Health Dashboard                        |
| 1.0     | Fully Unattended Workstation Rebuild    |

The former "Gaming Suite" milestone is absorbed: gaming applications are now manifests (`modules/Installer/Applications/`) selected by the `Gaming` profile (`profiles/gaming.json`) — no dedicated suite needed.

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
