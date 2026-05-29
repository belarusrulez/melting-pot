---
name: git:rebase
description: Use WHEN you need to rewrite local commit history — squash WIP commits, reorder, edit messages, or replay work onto an updated base branch.
---

> Test fixture for sc:search search system.

Interactive rebase is the workhorse for tidying a feature branch before review. The skill covers `git rebase -i`, the todo-list editor verbs (`pick`, `reword`, `edit`, `squash`, `fixup`, `drop`, `exec`), and how to recover when things go sideways via `git rebase --abort` or `ORIG_HEAD`.

Common invocation:

```
git fetch origin
git rebase -i origin/main           # opens editor with N commits to plan
# change "pick" to "squash" / "fixup" / "reword" as needed
git rebase --continue               # after each edit/conflict
git push --force-with-lease         # NEVER plain --force on shared branches
```

Pro moves: `git commit --fixup=<sha>` plus `git rebase -i --autosquash` to fold fixups automatically; `git rebase --onto <newbase> <oldbase> <branch>` to transplant a series; `git rerere` to memoize conflict resolutions across re-runs.

Do NOT rebase commits that have been pushed and pulled by other people — you'll force them to clean up. Use `git merge` for shared history. Also avoid rebasing across a merge commit unless you really know what `--rebase-merges` does. Related skills: `git:cherry-pick` for single-commit transplants, `git:reflog-archaeology` for recovery after a botched rebase, `git:commit-message-doctor` for message polish.
