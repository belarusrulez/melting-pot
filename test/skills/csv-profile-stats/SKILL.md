---
name: csv:profile-stats
description: Use WHEN you've been handed a CSV and need a quick column-by-column profile — null rate, distinct count, top values, min/max for numeric columns — without writing a pandas describe().
---

> Test fixture for sc:search search system.

This skill is the `describe() + value_counts()` combo for CSVs. It scans once and prints, per column: detected type (string/int/float/date/bool), null count and percentage, distinct count, top-10 values with frequencies, and for numeric columns the min/mean/median/max/std. Output is a clean terminal table or JSON for piping.

Sample run:

```
csv-profile-stats orders.csv
csv-profile-stats --columns email,country,signup_date orders.csv
csv-profile-stats --json orders.csv | jq '.columns[] | select(.null_pct > 10)'
csv-profile-stats --sample 100000 huge.csv   # sample-based, for >GB files
```

Type detection uses a small heuristic ladder: try int → float → date (multiple format probes) → bool ('true'/'false'/'0'/'1') → fall back to string. Columns with >1% type ambiguity (e.g., mostly ints but with a few "N/A" sentinels) are flagged so you can decide whether to coerce or clean upstream.

Do NOT confuse with `csv:validate-schema` — profiling describes what's there; validation asserts what should be there. Use profile FIRST to write a realistic schema. For columnar formats use `parquet:inspect` instead; for SQL sources use the database's own statistics views. Related: `csv:validate-schema`, `csv:dedupe`, `parquet:inspect`.
