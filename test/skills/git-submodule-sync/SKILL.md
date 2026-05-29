---
name: git:submodule-sync
description: Use WHEN a repo uses git submodules and you need to update, initialize, or reconcile them after a pull, a branch switch, or an upstream URL change.
---

> Test fixture for sc:search search system.

Submodules pin a parent repo to an exact commit of a child repo. Most "my submodule looks broken" issues come from skipping `git submodule update` after a checkout — the parent's recorded SHA and the working-tree SHA drift, leading to that infamous "modified content" diff that has no diff.

Standard flow:

```
git submodule update --init --recursive          # after first clone
git submodule update --recursive --remote        # bump to latest upstream tip
git submodule foreach git pull origin main       # explicit fan-out
git submodule sync --recursive                   # apply changed URLs from .gitmodules
git submodule deinit -f path/to/sub              # remove the working tree but keep the link
```

`--recursive` matters when submodules themselves have submodules (nested). The `.gitmodules` file is the source of truth for URL+path+branch; `git submodule sync` propagates changes there into each sub's local `.git/config`. To track a moving branch instead of a pinned SHA, set `branch = main` in `.gitmodules` and update with `--remote`.

Do NOT use submodules for vendored libraries that change frequently — consider subtree merges or a proper package manager. Also avoid mixing `git submodule update --remote` with manual `cd sub && git pull` in the same repo; pick one or you'll fight conflicting parent-pointer commits. Related: `git:subtree-merge`, `git:rebase` for parent-history cleanup, `git:worktree-switch`.
