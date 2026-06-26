# Branch Protection Settings

Applied as GitHub repository **rulesets** (`Settings → Rules → Rulesets`), via `gh api`. Classic branch protection and rulesets both require GitHub Pro on a private repo — the repo was made public on 2026-06-26 to unlock this on the free plan.

## Rule 1 — `main` (ruleset `main-protection`, id 18157754)

- Pull request required before merging
  - Approvals required: **0** — see note below on self-approval
  - Dismiss stale approvals on new commits: **on**
  - Required conversation resolution: **on**
- Required status checks (must be up to date with base branch):
  - `PowerShell Syntax & PSScriptAnalyzer`
  - `Validate JSON Configuration`
  - `Validate Markdown Links`
  - `Bootstrap Integrity`
- Linear history required
- No force pushes, no branch deletion
- No bypass actors — rules apply to everyone, including the repo owner

## Rule 2 — `develop` (ruleset `develop-protection`, id 18157755)

Same as `main`, except linear history is **not** required (merge commits allowed).

## Why required approvals = 0

GitHub blocks self-approval at the platform level — the "Approve" option is disabled in the UI and the API rejects it (`Can not approve your own pull request`) for the PR author, regardless of branch protection config. On a solo-maintainer repo this makes "require 1 approval" permanently unsatisfiable. We dropped it to 0 and rely on actually reading the diff before merging, rather than a rubber-stamp gate. If a second collaborator joins the project, raise `required_approving_review_count` back to 1.

## Repository settings

- Default branch: `develop`
- Delete branch on merge: enabled
- Visibility: public
- `feature/*`, `bugfix/*`, `docs/*`, `experiment/*` branches are intentionally **not** protected — disposable working branches.

## Re-applying or editing these rules

```powershell
gh api -X PUT repos/WebDevSH-Consult/Project-Phoenix/rulesets/18157754 --input ruleset_main.json
gh api -X PUT repos/WebDevSH-Consult/Project-Phoenix/rulesets/18157755 --input ruleset_develop.json
```

(JSON bodies mirror the rules listed above — see ruleset definitions in PR history or regenerate from this doc.)
