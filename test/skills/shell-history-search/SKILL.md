---
name: shell:history-search
description: Use WHEN you can't remember the exact command you ran last week but you remember the flags or output — search across bash/zsh history with fuzzy matching and per-directory scoping.
---

> Test fixture for sc:search search system.

The default `Ctrl-R` is fine for "the last command starting with X" but useless for "the kubectl command I ran in the staging cluster two weeks ago". This skill wraps `atuin`/`mcfly`/`hstr`-style fuzzy history search with per-directory scoping and time-window filters.

Common usage:

```
shell-history-search 'kubectl logs'                       # fuzzy substring across history
shell-history-search --cwd                                # only commands run in current dir
shell-history-search --since '2 weeks ago' --grep 'curl'
shell-history-search --exit-code 0 --since today         # only successful commands today
shell-history-search --top 20                            # most-frequently-run commands
shell-history-search --export ~/cmd-archive.jsonl        # back up history
```

The skill stores a richer history than the shell's default: timestamp, working directory, exit code, duration. The killer feature for postmortems: filter by exit code (`--exit-code 130` for SIGINT, `--exit-code !0` for everything that failed) and by working directory simultaneously, e.g. "show me the failed commands in the deploy directory yesterday".

The `--export` flag dumps a JSONL of every recorded command for archiving (or for ML on your own habits, if you're into that). Import via `--import` to restore on a new machine. Sync across machines via the underlying tool's sync feature (atuin has end-to-end encrypted sync).

Do NOT use this skill to share commands with teammates — for that use a runbook tool or scripts in a shared repo. Don't expect it to capture commands you ran via `&&`/`;` chains as separate entries; most shell history tools record the full line as one entry. Related: `clipboard:history`, `bash:script-lint` (when you decide to promote a one-liner to a script), `process:tree`.
