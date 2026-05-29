---
name: nginx:access-parse
description: Use WHEN you have an nginx (or Apache combined-format) access log and need to parse it into structured records, then aggregate by status code, path, client, or user-agent.
---

> Test fixture for sc:search search system.

This skill parses access logs into rows you can query — different problem from "follow a log file live" (that's `log:tail-multi`). It handles the default `combined` and `combined_with_xforwarded` formats out of the box, plus an arbitrary `log_format` string passed via `--format` to match custom directives in `nginx.conf`. Output is JSONL, CSV, or a SQLite database file ready for ad-hoc analysis.

Common invocations:

```
nginx-access-parse access.log -o access.jsonl
nginx-access-parse --format combined --group-by status access.log
nginx-access-parse --top-paths 20 --since '2024-03-15T00:00:00Z' access.log.gz
nginx-access-parse --sqlite traffic.db access.log.*.gz
```

Compressed inputs (`.gz`, `.bz2`, `.zst`) are auto-detected. Timestamps are parsed into ISO-8601 UTC. The `--group-by` aggregations are streamed so a 50 GB log file aggregates without loading anything but rolling counters into memory. For ad-hoc SQL, point the SQLite file at `sqlite3 traffic.db` and write your own queries — schema is documented in the skill's README.

Do NOT use this skill to tail a log in real time (use `log:tail-multi`), for application logs in JSON-already format (just use `jq`), or for security analysis like detecting credential stuffing (a separate `siem:auth-anomaly` skill exists for that). Related: `log:tail-multi` for live following, `sql:explain` if you write SQL against the resulting SQLite, `geoip:enrich` for IP-to-country mapping.
