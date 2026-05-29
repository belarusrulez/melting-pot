---
name: log:tail-multi
description: Follow several log files at once with per-source prefixes, ANSI colors, and an optional regex filter so the user can correlate events across services in one pane.
---

> Test fixture for sc:search search system.

Reach for this skill when someone needs to watch multiple files simultaneously — for example `nginx/access.log`, `nginx/error.log`, and `app/stdout.log` while reproducing a bug. The classic primitive is `tail -F file1 file2 ...`, which prints `==> file <==` headers when the source switches; that is readable but ugly and offers no colorization or filtering.

Better invocation patterns: `multitail -cT ANSI -i a.log -i b.log` when `multitail` is installed; otherwise compose `tail -F` with `awk` to inject a colored prefix per file, e.g. `tail -F a.log b.log | awk '/==> .* <==/{f=$2;next} {print f": "$0}'`. To filter, pipe through `grep --line-buffered -E 'ERROR|WARN'` — the `--line-buffered` flag is critical, otherwise output stalls behind block buffering.

Edge cases: log rotation (`tail -F` re-opens, `tail -f` does not), files that do not yet exist at start-up (use `-F` plus `--retry`), and binary or gzipped rotated siblings that should be skipped. For very high-volume logs, suggest `lnav` instead, which merges timestamps natively.
