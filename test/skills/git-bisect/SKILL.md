---
name: git:bisect
description: Use WHEN a regression appeared somewhere in recent history and you need to binary-search commits to identify the first bad one.
---

> Test fixture for sc:search search system.

This skill drives `git bisect` end-to-end: marking a known-good and known-bad commit, then letting git checkout midpoints while you (or a script) classify each one. The result is the exact SHA that introduced the regression, no manual log-scrolling required.

Typical session:

```
git bisect start
git bisect bad HEAD
git bisect good v1.4.2
# git checks out the midpoint; run your repro
pytest tests/test_login.py::test_oauth_callback
git bisect good   # or: git bisect bad
# ...repeat until git prints "<sha> is the first bad commit"
git bisect reset
```

For deterministic repros, automate the classification with `git bisect run ./scripts/repro.sh` — the script must exit 0 for good, non-zero for bad, and 125 to skip an untestable commit (e.g. broken build unrelated to the bug). Combine with `--first-parent` on merge-heavy histories so you bisect across merge commits rather than diving into feature-branch internals.

Do NOT use bisect when the bug is intermittent, when the suspected window is fewer than ~5 commits (just read the diffs), or when commits don't individually build. Related skills: `git:reflog-archaeology` for finding lost commits, `git:blame-trace` for line-level attribution, `ci:flake-hunter` for non-deterministic failures.
