# Branch Protection Settings

Apply these via GitHub web UI: **Settings → Branches → Add branch protection rule**. (No `gh` CLI / GitHub connector available in this session to apply them automatically — do this manually once.)

## Rule 1 — `main`

Branch name pattern: `main`

- [x] Require a pull request before merging
  - [x] Require approvals — **1**
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [ ] Require review from Code Owners (optional — enable once CODEOWNERS coverage is broader than one person)
- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Required checks (once CI has run at least once on a PR, these become selectable):
    - `PowerShell Syntax & PSScriptAnalyzer`
    - `Validate JSON Configuration`
    - `Validate Markdown Links`
    - `Bootstrap Integrity`
- [x] Require conversation resolution before merging
- [x] Require linear history
- [x] Do not allow bypassing the above settings (applies rules to admins too)
- [ ] Allow force pushes — leave **unchecked**
- [ ] Allow deletions — leave **unchecked**

## Rule 2 — `develop`

Branch name pattern: `develop`

- [x] Require a pull request before merging
  - [x] Require approvals — **1**
  - [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Same required checks as `main`
- [x] Require conversation resolution before merging
- [ ] Require linear history — optional, enable if you want to disallow merge commits and force squash/rebase
- [ ] Allow force pushes — leave **unchecked**
- [ ] Allow deletions — leave **unchecked**

## Notes

- `feature/*`, `bugfix/*`, `docs/*`, `experiment/*` branches are intentionally **not** protected — they're disposable working branches.
- Until the first CI run completes on a PR, the "Required checks" list in GitHub's UI will be empty (it only lists checks that have run at least once). Open the foundation PR first, let CI run, then come back and tick the four checks above.
- Repository setting **Settings → General → Pull Requests**: enable "Automatically delete head branches" so merged `feature/*` branches don't pile up.
- Repository setting **Settings → General**: set default branch to `develop` so new clones/PRs target it instead of `main`.
