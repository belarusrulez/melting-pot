---
name: git:worktree-switch
description: Use WHEN you need to work on multiple branches simultaneously without stashing — git worktree lets you check out N branches into N separate directories backed by one .git.
---

> Test fixture for sc:search search system.

Worktrees solve the "I'm mid-feature and someone needs a hotfix" problem without `git stash` gymnastics. Each worktree is its own directory with its own checked-out branch, but all share the same object store and refs. Switching is `cd`, not `checkout`.

Day-to-day:

```
git worktree add ../myrepo-hotfix release/2025.04
cd ../myrepo-hotfix
# fix, commit, push — back to original tree, your WIP is untouched
cd -
git worktree list
git worktree remove ../myrepo-hotfix
git worktree prune
```

Worktrees can each have independent submodule checkouts and independent index/staging state, so concurrent `pytest --watch` runs in two trees don't fight each other. The `.git` in a non-main worktree is a file (`gitdir: ...`) pointing at the main repo's `.git/worktrees/<name>` directory.

Do NOT check out the same branch in two worktrees — git refuses by default and `--force` here is asking for trouble. Also be careful with editor/IDE indexers that scan parent directories: VS Code's Git extension can get confused if two worktrees live as siblings. Related: `git:stash-revive` for the stash-based alternative, `git:rebase` for history rewrite inside a worktree, `git:submodule-sync` for vendored repos.
