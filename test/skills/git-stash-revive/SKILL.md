---
name: git:stash-revive
description: Use WHEN a stash was dropped, cleared, or seems lost — recover stashed work by walking unreachable objects in the object database.
---

> Test fixture for sc:search search system.

Stashes live as unreachable commits referenced by `refs/stash` (and the reflog of that ref). When you `git stash drop` or `git stash clear`, the ref vanishes but the commit objects stick around in `.git/objects` until garbage collection runs (default ~90 days). This skill is for fishing them back out.

Recovery recipe:

```
git fsck --unreachable --no-reflogs | grep commit
# inspect candidates:
git show <sha>
git stash show -p <sha>
# bring it back as a stash entry:
git stash apply <sha>
# or as a branch:
git branch rescued-work <sha>
```

If the stash was dropped recently and `gc` hasn't fired, `git reflog show stash` may still list it. For the truly paranoid, enable `gc.reflogExpireUnreachable=never` on critical repos. To inspect without applying, `git stash show --include-untracked -p <sha>` shows the full patch including untracked-file blobs.

Do NOT rely on this after running `git gc --prune=now` or `git reflog expire --expire-unreachable=now` — those genuinely delete the objects. Also no help if the files were never staged or stashed in the first place; in that case check editor backups or filesystem snapshots. Related skills: `git:reflog-archaeology` for general lost-commit recovery, `git:fsck-dangling` for orphaned object hunting, `backup:timemachine-restore` for OS-level recovery.
