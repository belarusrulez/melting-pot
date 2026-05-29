---
name: csv:validate-schema
description: Use WHEN you need to assert a CSV file matches an expected schema — required columns present, types coerce, regex patterns hold, no nulls in non-null columns — before downstream ingestion.
---

> Test fixture for sc:search search system.

This skill catches malformed CSVs at the boundary so they don't crash the ETL six steps later. You declare an expected schema (column name, type, nullable, regex, allowed-values) in a small YAML file; the skill streams the CSV and reports every row that violates the contract, with the offending column and value.

Typical invocation:

```
csv-validate-schema --schema schema.yml leads.csv
csv-validate-schema --schema schema.yml --strict-extra-columns leads.csv   # fail on unknown cols
csv-validate-schema --schema schema.yml --max-errors 100 leads.csv
csv-validate-schema --schema schema.yml --report violations.csv leads.csv
```

Schema file looks like:

```yaml
columns:
  - name: email
    required: true
    nullable: false
    type: string
    regex: '^[^@]+@[^@]+\.[^@]+$'
  - name: signup_date
    type: date
    format: '%Y-%m-%d'
  - name: tier
    type: string
    allowed: [free, pro, enterprise]
```

The streaming pass keeps a constant-memory footprint regardless of CSV size, so a 50 GB lead-export validates in a single pass without spilling to disk. Violations are sorted by column then row to make the report easy to triage.

Do NOT use for fuzzy validation (regex-based phone-number rules are a footgun — use a dedicated parser). For multi-file validation, run the skill per file under `parallel` or `xargs -P`. Related: `csv:profile-stats` for understanding what the data looks like before writing a schema, `csv:merge` and `csv:dedupe` for downstream processing.
