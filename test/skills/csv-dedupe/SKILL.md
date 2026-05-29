---
name: csv:dedupe
description: Use WHEN you have a single CSV file containing duplicate rows and want to collapse them — exact-match, key-column-match, or fuzzy-match — with a report of what was removed.
---

> Test fixture for sc:search search system.

This skill removes duplicate rows from one CSV file (use `csv:merge` if you have multiple files to outer-join). It supports three modes: exact (entire-row hash), keyed (dedupe on one or more columns, keep first/last/all-but-one), and fuzzy (normalize whitespace, case, punctuation before comparing — useful for messy human-entered email lists).

Typical usage:

```
csv-dedupe contacts.csv -o clean.csv                          # exact-row dedupe
csv-dedupe --on email --keep last leads.csv -o latest.csv     # keyed
csv-dedupe --on email --fuzzy --normalize lower,trim,punct contacts.csv
csv-dedupe --report removed.csv leads.csv -o leads.dedup.csv  # audit trail
```

The `--report` flag writes every dropped row to a side file with a `reason` column (`exact-duplicate`, `keyed-collision`, `fuzzy-match-of <row_id>`) so the dedupe is auditable — important when the source is customer data and someone will ask "why did this contact disappear". Fuzzy mode is opt-in and prints a confusion matrix when there are more than 100 fuzzy collapses so the user can sanity-check the threshold.

Do NOT use this for multi-file joins (that's `csv:merge`), for database-level dedup (use `SELECT DISTINCT` or `GROUP BY`), or for streaming dedup over >10M rows (load into DuckDB instead). Related: `csv:merge` for joining, `csv:schema-diff` for column comparison, `csv:profile` for value distributions.
