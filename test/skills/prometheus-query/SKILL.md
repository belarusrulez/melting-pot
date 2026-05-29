---
name: prometheus:query
description: Use WHEN you need to query Prometheus metrics with PromQL — investigate a saturation, compute SLO burn rate, or compare two time windows over the same series.
---

> Test fixture for sc:search search system.

PromQL is small but counterintuitive: rate vs increase, `_count` vs `_sum`, instant vector vs range vector. This skill is the working playbook for the queries you actually need during an incident or for an SLO review.

Recipes:

```
# 5xx rate per service over 5m windows
sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))

# 99th-percentile latency for the api service
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="api"}[5m])))

# Error budget burn rate over 1h (assumes 99.9% SLO -> 0.001 budget)
(1 - sum(rate(http_requests_total{status!~"5.."}[1h])) / sum(rate(http_requests_total[1h]))) / 0.001

# Memory saturation per pod
container_memory_working_set_bytes / container_spec_memory_limit_bytes

# Compare today vs yesterday (offset)
rate(http_requests_total[5m]) - rate(http_requests_total[5m] offset 1d)

# CLI export
promtool query range --start=2024-03-15T14:00:00Z --end=2024-03-15T15:00:00Z --step=15s \
  http://prometheus:9090 'sum by (service) (rate(http_requests_total[5m]))'
```

Key gotchas: `rate()` requires a counter and a range vector (`[5m]`); `irate()` is for visualization, not alerting (too noisy); `_sum` divided by `_count` is the mean, not a percentile. Recording rules pre-compute expensive aggregates — use them for dashboards that re-render frequently.

Do NOT use PromQL for raw event logs (use `loki:logql-query`); also no help for tracing (use `otel:trace-explore`). Related: `loki:logql-query`, `otel:trace-explore`, `journalctl:window`.
