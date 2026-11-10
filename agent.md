# Working rules for this repository

The rules for all shrippen repositories are in `RULES.md` (writing, code, commits, bug
fixes, repository, GUI). It is a synced copy from the rules repository; do not edit it
here. This file holds only what is particular to this repository. A Claude Code session on
the owner's machine has the rules through the global `CLAUDE.md` already and reads
`RULES.md` only for its GUI rule, before work on a user interface.

## QML lint

- `scripts/qmllint.sh`, also in CI (reports, does not block). A finding in `contents/ui/Kante*` is fixed in Kante, then `scripts/sync-kante.sh`.
- **`var` in blocks, review when you touch a file:** Qt 6.12 reports every `var` inside a block (`block-scope-var-declaration`, about 200 here, October 2026); the rule is off in the script, the code works as written. When you change a file anyway, switch its `var`s to `let`/`const`, but check each: if the variable is read after its block or by a closure relying on function scope, `let` breaks it, at runtime only. Run the unit tests and try the view afterwards. A file's cases: `/usr/lib/qt6/bin/qmllint -I contents/ui --json - <file>`.

## Release

Release steps: `RELEASE.md`. Before a release, load the skill `release-changelog`. A release
is published, so the owner confirms it in words.

## Repository (this project)

- CI runs on the GitHub mirror (`.github/workflows/checks.yml`, since 16.10.2026) and reports back to Gitea as the commit status `github / test`.
- The merge waits for: CI is green on the PR's latest commit: every CI check that runs on each push (such as `github / test` from the GitHub mirror) shows success there.
- The owner also confirms: `packaging/`.
- Everything else: `RULES.md` (Repository) and the skill `pr-review`.
