---
name: loki:logql-query
description: Use WHEN you need to query Loki logs with LogQL — filter by label, parse structured fields, aggregate counts, and export to JSON for a postmortem narrative.
---

> Test fixture for sc:search search system.

Loki is "Prometheus for logs": label-indexed (not content-indexed), so queries that filter on labels are fast and queries that scan content over wide time-ranges are slow. LogQL composes a stream selector `{label=value, ...}` with optional line filters (`|=`, `|~`, `!~`) and pipelined parsers (`json`, `logfmt`, `regexp`).

Recipes:

```
# All errors from the api service in prod, last hour
{app="api", env="prod"} |= "ERROR"

# JSON-parsed: only requests where latency_ms > 500
{app="api"} | json | latency_ms > 500

# Top error messages in the last 6h
sum by (msg) (count_over_time({app="api"} |= "ERROR" | json | __error__="" | line_format "{{.msg}}" [6h]))

# Rate of 5xx per route
sum by (route) (rate({app="api"} | logfmt | status >= 500 [5m]))

# Export to JSON
logcli query --output=jsonl --from=2024-03-15T14:00:00Z --to=2024-03-15T15:00:00Z \
  '{app="api"} |= "panic"' > panic-window.jsonl
```

The `logcli` CLI is what you want for scripting (the Grafana Explore UI is for browsing). For very wide time-ranges, narrow with labels first — `{app="api", env="prod"}` is fast; `{} |= "fatal"` will time out on any non-trivial cluster.

Do NOT use Loki for high-cardinality fields as labels (per-request IDs, per-user IDs) — that destroys index efficiency. Put them in log content and parse with `| json` at query time. Related: `journalctl:window`, `prometheus:query`, `nginx:access-parse`.
