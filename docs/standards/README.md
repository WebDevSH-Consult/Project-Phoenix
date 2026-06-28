# Standards

## Purpose

Holds the concrete, operational rules that govern how the repository is configured and maintained — as opposed to [docs/adr](../adr/README.md), which records *why* a rule was chosen.

## Scope

Repository-level configuration standards such as branch protection rules, required CI checks, and naming conventions. See [branch-protection.md](./branch-protection.md) for the current rulesets applied to `main` and `develop`.

## Expected Contents

One document per standard, updated in place as the underlying configuration changes (e.g. when a new required CI check is added). Unlike ADRs, these are living documents that should always reflect current reality, not historical decisions.
