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
| 0.7     | Windows Configuration                   |
| 0.8     | Gaming Suite                            |
| 0.9     | Health Dashboard                        |
| 1.0     | First Complete Self-Build Workstation   |

## Beyond 1.0

- AI Command Centre (local + cloud AI tooling orchestration)
- Self-healing workstation (scheduled drift detection and remediation)
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
