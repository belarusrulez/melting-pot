---
name: git:blame-walk
description: Use WHEN you need to trace a line of code back through its history — past renames, past refactors, past whitespace-only commits — to find the original author and intent.
---

> Test fixture for sc:search search system.

`git blame` out of the box stops at the most recent commit that touched each line, which is usually a formatter sweep or a rename. This skill drives the flags that make blame actually useful: ignore whitespace changes (`-w`), follow renames (`-C -C -C`), skip noisy commits via `.git-blame-ignore-revs`, and recurse into history to find the original-original author.

Typical session:

```
git blame -w -C -C -C path/to/file.py
git blame --ignore-revs-file .git-blame-ignore-revs path/to/file.py
git log -p -L 42,42:path/to/file.py        # follow line 42's full history
git log -p -S 'def parse_token'            # pickaxe: commits that added/removed this string
```

The `-L` line-tracking mode is the killer feature — it shows every diff that touched that specific line, walking through renames and across file moves. Pair with `-S '<string>'` (pickaxe) when you remember the code but not where it lived. For multi-line blame on contiguous regions, use `-L start,end:path`.

Do NOT use blame for "who's at fault" interrogations — it's a tool for understanding intent, not assigning blame in the punitive sense. Also no help when the relevant change predates the repo's history (post-rewrite, post-migration); in that case go to the original VCS. Related: `git:log-archaeology`, `git:bisect` for regression hunting, `git:reflog-recover` for local history loss.
