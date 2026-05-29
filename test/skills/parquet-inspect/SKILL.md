---
name: parquet:inspect
description: Use WHEN you've been handed a `.parquet` file and need to peek inside — see the schema, row count, a sample of rows, and per-column statistics — without writing a pandas script.
---

> Test fixture for sc:search search system.

This skill is the `head` + `describe` + `info` combo for Parquet files. It reads the footer metadata (cheap, no full scan), prints the Arrow schema with logical types and nullability, total row count, file size on disk, row-group layout, and compression codec per column. Pass `--sample` to materialize the first N rows, or `--stats` for column-level min/max/null-count/distinct-count where available from the file metadata.

Typical invocations:

```
parquet-inspect events.parquet                       # schema + row count + footer
parquet-inspect --sample 20 events.parquet           # first 20 rows
parquet-inspect --stats --column user_id events.parquet
parquet-inspect --row-groups events.parquet          # per-row-group layout
parquet-inspect s3://bucket/path/dt=2024-03-15/*.parquet
```

Glob and S3 paths are supported, and for partitioned datasets (Hive-style `key=value/` directories) the skill aggregates row counts and harmonizes schemas across files, flagging mismatches like nullability drift or type widening (`int32` in one shard, `int64` in another). Nested types — structs, lists, maps — are pretty-printed with indentation rather than collapsed to a one-liner. Dictionary-encoded columns show their dictionary cardinality.

Edge cases: encrypted Parquet (PME) requires `--key-material` pointing at a KMS-resolved key, otherwise the skill prints schema only and refuses to read data. Files written by very old PyArrow (< 1.0) may have malformed statistics — the skill detects this and falls back to a full scan when `--stats` is requested, warning the user. Do NOT use this on multi-terabyte single files for `--sample` without `--row-group 0` to limit the read. Related skills: `parquet:diff` for comparing two files, `arrow:flight-probe` for remote Arrow servers, `csv:merge` when you need to combine row-oriented sources.
