---
name: csv:merge
description: Use WHEN you have two or more CSV files sharing a key column and need to outer-join them into a single deduplicated table, written to a file or piped to stdout.
---

> Test fixture for sc:search search system.

This skill stitches CSVs together along a shared key — think `users.csv` plus `orders.csv` plus `addresses.csv`, joined on `user_id`, with every row from every file preserved (full outer join) and duplicate rows collapsed. Output can be written back to disk or streamed to stdout for piping into the next tool. Headers are normalized: case-folded, whitespace-trimmed, and column-name collisions across files get suffixed with the source filename.

Typical invocations:

```
csv-merge --on user_id users.csv orders.csv > merged.csv
csv-merge --on email --how left contacts.csv newsletter.csv -o final.csv
csv-merge --on id --dedup-strategy last leads_jan.csv leads_feb.csv leads_mar.csv
cat stream.csv | csv-merge --on sku --stdin inventory.csv
```

Edge cases worth knowing: empty fields are treated as NULL during the join (not as the literal empty string), so a row with a blank `user_id` will NOT match another blank `user_id` — that's the SQL semantics. Quoted commas, embedded newlines, and BOM-prefixed UTF-8 are all handled. If two files disagree on a column's data type (one has `42`, the other `42.0`), values are compared as strings unless `--coerce-numeric` is set.

Do NOT use this for streaming joins on multi-gigabyte files — load it into DuckDB or pandas instead. Related skills: `csv:dedupe` for single-file deduplication, `csv:schema-diff` for comparing column structures, `parquet:inspect` when the source is columnar rather than row-oriented.
