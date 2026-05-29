---
name: merge:conflict-resolver
description: Use WHEN git reports CONFLICT during merge, rebase, cherry-pick, or stash apply — walks through three-way resolution, hunk selection, and verification.
---

> Test fixture for sc:search search system.

When two branches touch the same lines, git stops and asks you to choose. This skill is the structured playbook: identify conflicting files, understand the three-way context (ours / theirs / base), pick the right hunks, and verify the result before continuing the operation.

Workflow:

```
git status                                    # see "Unmerged paths"
git diff --name-only --diff-filter=U          # just the conflict list
git mergetool                                 # or open files manually
# conflict markers look like:
#   <<<<<<< HEAD
#   ours
#   =======
#   theirs
#   >>>>>>> feature/xyz
git checkout --ours path/to/file              # take our side wholesale
git checkout --theirs path/to/file            # take their side wholesale
git add <resolved-files>
git merge --continue                          # or rebase/cherry-pick --continue
```

For semantic conflicts (code merges cleanly but is logically broken), always run the test suite after resolution. Use `git mergetool --tool=vimdiff` (or `meld`, `kdiff3`, VS Code's built-in 3-way view) for visual hunk selection. Enable `git config rerere.enabled true` so repeated conflicts during long rebases auto-resolve from memory.

Do NOT blindly `git checkout --theirs .` to make conflicts disappear — that silently throws away your work. Also be wary of binary file conflicts (images, lockfiles); regenerate lockfiles from scratch rather than hand-merging. Related skills: `git:rebase` and `git:cherry-pick` (which trigger this skill on conflict), `package:lockfile-merge` for `package-lock.json` / `yarn.lock` / `Cargo.lock` specifics, `git:rerere-setup` for resolution memoization.
