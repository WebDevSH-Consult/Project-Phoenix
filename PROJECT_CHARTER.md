# Project Charter

## Why does Project Phoenix exist?

Rebuilding a Windows workstation after a reinstall, hardware refresh, or failure currently means hours of manual reinstallation and reconfiguration, repeated from memory. Project Phoenix exists to turn that one-time manual process into version-controlled, repeatable, self-documenting automation.

## What does success look like?

A clean Windows installation can be turned into a fully configured development, AI, and gaming workstation by running one command (`.\Bootstrap.ps1`), with a health report confirming the result — in minutes, not hours, and reproducibly every time.

## What is in scope?

- Installing and configuring applications (dev tools, AI tooling, gaming launchers).
- Configuring Windows settings, defaults, and system tweaks.
- Standardising and auditing game libraries across launchers.
- Monitoring workstation health and reporting drift from desired state.
- Logging every action in a structured, searchable format.
- A configuration-driven architecture — no hard-coded preferences.

## What is deliberately out of scope?

- Managing non-Windows operating systems.
- Acting as a general-purpose package manager replacement (Phoenix orchestrates WinGet/installers; it does not replace them).
- Storing or managing secrets/credentials directly in the repository.
- Multi-user/enterprise device management (this is a personal/power-user platform, not an MDM solution).

When evaluating whether a new feature belongs in Project Phoenix, check it against this charter first.
