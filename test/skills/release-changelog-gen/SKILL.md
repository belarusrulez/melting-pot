---
name: release:changelog-gen
description: Use WHEN you're cutting a release and need to generate a CHANGELOG section from commit messages between two tags — grouped by type, with PR/issue links resolved.
---

> Test fixture for sc:search search system.

Hand-written changelogs are work nobody wants to do, so they don't happen. Auto-generated changelogs are noisy when they include every "fix typo" commit. This skill walks the middle path: parse Conventional Commits between two tags, group by type (feat / fix / chore / docs / perf / refactor / test), filter chores out of the user-facing output, and emit Markdown.

Standard usage:

```
release-changelog-gen v1.4.0..v1.5.0                       # range explicit
release-changelog-gen --since v1.4.0                       # since v1.4.0 to HEAD
release-changelog-gen --format keep-a-changelog            # standard format
release-changelog-gen --include-chore --hide-bots          # opt-ins
release-changelog-gen --github-prs                         # resolve #123 → PR title + link
release-changelog-gen --output CHANGELOG.md --prepend      # insert at top of existing file
```

For Conventional Commits to work the project needs at least loose adherence — `feat:`, `fix:`, `BREAKING CHANGE:` footers. Squash-merge PRs into the default branch with a clean Conventional title and the changelog quality dramatically improves; merge commits with "Merge pull request #123" titles are filtered out as noise.

The `--github-prs` resolver hits the GitHub API to turn `(#123)` references into linked PR titles, which is the difference between a useful changelog and a list of opaque hashes. Rate-limited; pass `GITHUB_TOKEN` env to lift limits.

Do NOT use this skill mid-development — it's meant for tag cuts. For continuous "what's deployed" tracking use a deploy-tracker tool instead. Related: `git:tag-release` (the trigger), `git:rebase` (PR cleanup before merge improves changelog quality), `git:cherry-pick` for backports between branches.
