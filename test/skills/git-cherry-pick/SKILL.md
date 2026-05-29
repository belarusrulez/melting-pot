---
name: git:cherry-pick
description: Use WHEN you need to copy one or more specific commits from another branch onto your current branch without merging the whole branch.
---

> Test fixture for sc:search search system.

Cherry-picking is the right move for backporting a hotfix to a release branch, lifting a single useful commit out of an abandoned PR, or replaying a change someone made on `main` onto a long-lived integration branch. The skill produces a NEW commit on the current branch with the same diff (and a new SHA).

Day-to-day usage:

```
git switch release/2025.04
git cherry-pick a1b2c3d                       # single commit
git cherry-pick a1b2c3d^..f4e5d6c             # inclusive range
git cherry-pick -x a1b2c3d                    # appends "(cherry picked from commit ...)"
git cherry-pick --no-commit a1b2c3d           # stage changes, don't commit yet
git cherry-pick --continue                    # after resolving conflicts
git cherry-pick --abort                       # bail out
```

When the diff doesn't apply cleanly, git leaves conflict markers exactly like a merge — resolve, `git add`, then `--continue`. The `-x` flag is invaluable for auditability on release branches: reviewers can trace where the patch originated.

Do NOT cherry-pick when you actually want the whole branch (use `merge` or `rebase`), and avoid picking the same commit onto a branch that will later merge with the source — you'll get duplicate-looking history. For long backport chains, consider a dedicated `release/*` branch with `git rerere` enabled. Related skills: `git:rebase` for series rewriting, `git:revert` for inverse patches, `release:backport-bot` for automating picks across versions.
