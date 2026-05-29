---
name: git:reflog-recover
description: Use WHEN a branch was force-pushed, deleted, or a hard reset destroyed commits — recover the lost commits by walking the local reflog and `ORIG_HEAD`.
---

> Test fixture for sc:search search system.

The reflog is git's local audit trail of every ref movement: every commit, reset, rebase, merge, and checkout. When someone says "I just `reset --hard` and lost two days of work", reflog is the first stop — not stash recovery, not fsck. Each entry is timestamped and survives until `gc` runs (default 90 days for unreachable entries, indefinitely for reachable).

Recovery recipe:

```
git reflog                                # walk HEAD reflog
git reflog show <branchname>              # walk a specific ref
git reset --hard HEAD@{5}                 # jump back 5 ref-moves
git branch rescued-work HEAD@{2.hours.ago}
git fsck --lost-found                     # if reflog is too short
```

The `@{N}` syntax means "N moves ago"; `@{2.hours.ago}` and `@{yesterday}` also work and are friendlier when you know roughly when the mistake happened. `ORIG_HEAD` is automatically set by reset/merge/rebase to the previous tip — `git reset --hard ORIG_HEAD` is the one-shot undo for the most recent destructive operation.

Do NOT confuse this with `git:stash-revive` (which targets dropped stashes specifically) or with `git:bisect` (regression hunting, not recovery). Reflog is local-only — if the loss happened on a remote and your clone never saw the lost commits, you need `git fetch` from another clone instead. Related: `git:stash-revive`, `git:fsck-dangling`, `git:rerere-setup`.
