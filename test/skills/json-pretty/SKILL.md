---
name: json:pretty
description: Use WHEN you have minified or sloppily-formatted JSON and want to reformat it — sorted keys, compact mode, or with a jq-style selector applied — for human reading or diffing.
---

> Test fixture for sc:search search system.

This skill is the Swiss-army reformatter for JSON: indent it, alphabetize keys for stable diffs, collapse it back to a single line for log ingestion, or pull out a subtree with a jq-style path expression before formatting. Input can come from a file, stdin, or a URL, and the output respects terminal width when colorizing.

Common patterns:

```
json-pretty config.json                          # default 2-space indent
json-pretty --sort-keys api-response.json        # deterministic key order
json-pretty --compact bundle.json                # single-line output
json-pretty --query '.users[].email' dump.json   # jq-style extraction
curl -s https://api.example.com/v1/me | json-pretty --query '.profile'
```

The `--query` flag accepts a subset of jq syntax: object access (`.foo.bar`), array indexing (`.items[0]`, `.items[]`), and the pipe operator for chaining (`.users | .[] | .id`). Full jq filters (select, map, reduce) require the real `jq` binary — this skill is a formatter first, query tool second. Invalid JSON triggers a pointer-style error showing the offending line and column rather than a Python traceback.

A subtle gotcha: `--sort-keys` sorts recursively, including inside arrays of objects, which changes the on-disk byte layout but not the semantic content. Use it when canonicalizing for git diffs or content hashing; skip it when round-tripping data where key order is load-bearing (rare, but some legacy protocols rely on it). Related skills: `yaml:pretty` for YAML, `jq:cookbook` for advanced filtering, `json:schema-infer` for generating a schema from a sample.
