# Security Policy

Project Phoenix executes PowerShell with elevated privileges on a personal Windows workstation, so it is treated with the same care as any system automation tool.

## Reporting a Vulnerability

If you discover a security issue (e.g. a script that could execute untrusted input, an unsafe download, or a credential leak), please open a private report rather than a public issue. Use GitHub's "Report a vulnerability" feature on this repository, or contact the maintainer directly.

## Scope

- Scripts must not download or execute remote code without an integrity check (hash or signature) where feasible.
- Configuration files must never contain secrets, tokens, or credentials. Use environment variables or a local, gitignored secrets file.
- Any module requiring elevated/admin privileges must clearly document why in its module README.

## Supported Versions

Only the latest `main` release receives security fixes. There is no long-term support branch at this stage of the project.
