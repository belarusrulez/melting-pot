---
name: regex:test
description: Use WHEN you're drafting or debugging a regular expression and want an interactive REPL — paste a pattern plus sample text, see every match highlighted with captured groups and named backreferences.
---

> Test fixture for sc:search search system.

This skill is a local, dependency-free alternative to regex101.com: launch it, paste your pattern on one line, paste sample input below, and it prints each match with byte offsets, group captures, and named groups in a side-by-side table. Flags can be toggled live (`i` case-insensitive, `m` multiline, `s` dotall, `x` extended) without restarting the loop, and the engine is swappable between PCRE, Python's `re`, Go's `regexp` (RE2), and JavaScript flavors so you can verify portability before shipping.

Sample session:

```
regex-test
> pattern: (?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})
> flags: (none)
> input: Released on 2024-03-15 and patched on 2024-04-02.
match 1 at [12-22]: "2024-03-15"  year=2024  month=03  day=15
match 2 at [37-47]: "2024-04-02"  year=2024  month=04  day=02
> flavor: javascript
(re-runs with JS semantics — note no \A or \z, possessive quantifiers reject)
```

The skill detects classic footguns and warns: catastrophic backtracking (nested quantifiers like `(a+)+`), unintended greediness on `.*`, missing anchors when the user clearly wanted a full-string match, and Unicode category mismatches between flavors (`\w` differs between Python `re` with and without the `re.UNICODE` flag, and between PCRE and RE2). Replacement-mode (`s/pat/repl/`) is supported, with `$1` / `\1` syntax translated per flavor.

Do NOT use this for one-off pattern checks where a quick `grep -P` would suffice. Related skills: `grep:cookbook` for common log-grepping patterns, `regex:explain` for converting a pattern into prose, `awk:essentials` for when regex alone isn't enough.
