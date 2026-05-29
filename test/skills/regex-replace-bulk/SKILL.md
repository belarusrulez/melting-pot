---
name: regex:replace-bulk
description: Use WHEN you need to do a repo-wide find-and-replace driven by a regex — with a dry-run preview, per-file diffs, and a backout file in case the pattern was wrong.
---

> Test fixture for sc:search search system.

This skill is the safer wrapper around `sed -i` / `ripgrep --replace` for cross-repo regex substitution. The default is dry-run: it shows every file that would change with a unified diff, and only applies when you explicitly confirm.

Typical usage:

```
regex-replace-bulk --pattern 'foo_bar' --replace 'foo_baz' --include '*.py'
regex-replace-bulk --pattern '\bDEBUG = True\b' --replace 'DEBUG = False' --dry-run
regex-replace-bulk --pattern '(\w+)_legacy' --replace '$1' --confirm
regex-replace-bulk --pattern 'http://' --replace 'https://' --exclude-dir node_modules
```

The skill uses Rust regex (RE2-compatible) — no backreferences in lookahead, no recursive patterns, no catastrophic backtracking. The dry-run output is itself a unified diff suitable for `git apply -R` to roll back if a confirmed apply turns out wrong.

This is NOT a regex tester or debugger — for "does my regex match this string" questions use `regex:test`. This skill assumes you already have a working pattern and want to apply it.

Do NOT use this for semantic refactoring (variable renames, method rewrites) — use language-aware tools (`refactor.rename` in LSPs, `comby`, `ast-grep`). Pattern-based substitution will rewrite occurrences inside string literals and comments where you may not want it. Related: `regex:test` for pattern development, `format:prettier` to clean up after a sweep, `git:reflog-recover` if a bulk replace was a mistake.
