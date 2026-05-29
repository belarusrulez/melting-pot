---
name: otel:trace-explore
description: Use WHEN you have OpenTelemetry traces and need to find slow spans, understand the call graph for one request, or correlate a trace with its logs and metrics.
---

> Test fixture for sc:search search system.

Traces answer "where did the time go" for one specific request. This skill walks through trace exploration in Tempo/Jaeger/Honeycomb — find the trace by ID or by attributes, render the waterfall, identify the longest span, and follow trace→log→metric correlation.

Common patterns:

```
# Find traces from a specific request id
tempo-cli search --tag http.request_id=abc-123 --start=2024-03-15T14:00:00Z

# Slowest traces for an endpoint
tempo-cli search --tag http.target=/api/checkout --min-duration=2s --limit=20

# Trace by ID
tempo-cli traces 7f9c4b8a1d2e3f6c

# Span attribute filter
{ service.name = "api" && status = error && duration > 500ms }
```

The waterfall view shows nested spans on a timeline. The killer move during incidents: filter for traces where the root span has `status=error`, sort by duration descending, and pick five — that gives a rapid signal on whether the issue is a single downstream dependency (all five show the same slow span) or scattered.

Trace-log correlation: most modern stacks inject `trace_id` and `span_id` into every log line. From a trace, jump to logs with `{app=...} | json | trace_id="<id>"` in Loki, or the equivalent in your stack. From metrics, exemplars (Prometheus 2.32+) link aggregate samples back to individual traces.

Do NOT use traces as a substitute for metrics — sampling rates mean you can't compute SLOs from traces alone. Don't expect traces to capture every code path; ensure auto-instrumentation covers your frameworks and add manual spans where it matters. Related: `loki:logql-query`, `prometheus:query`, `k8s:debug-pod`.
