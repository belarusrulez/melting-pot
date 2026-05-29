---
name: sql:explain
description: Use WHEN a SQL query is slow and you need to visualize its EXPLAIN plan as a readable tree, surface missing-index hints, or share the plan as a Mermaid diagram in a PR review.
---

> Test fixture for sc:search search system.

This skill ingests the output of `EXPLAIN`, `EXPLAIN ANALYZE`, or `EXPLAIN (FORMAT JSON)` from Postgres, MySQL, or SQLite, and renders the operator tree as either ASCII art (for terminal sharing) or Mermaid (for pasting into a Markdown doc or GitHub issue). Each node is annotated with estimated rows, actual rows, cost, and timing — and rows where the estimate is off by more than 10x are highlighted as planner-stat-staleness suspects.

Typical flow:

```
sql-explain plan.txt                                    # ASCII tree
sql-explain --format mermaid plan.txt > plan.md         # Mermaid output
psql -c 'EXPLAIN ANALYZE SELECT ...' | sql-explain --stdin
sql-explain --hint-indexes plan.txt                     # missing-index advice
sql-explain --dialect mysql plan-mysql.txt
```

The `--hint-indexes` mode scans for sequential scans on large tables, hash joins where a merge join would be cheaper, and nested-loop joins driving more than ~10k rows on the outer side. Each finding is paired with a suggested `CREATE INDEX` statement — but these are suggestions, not commands; the skill never executes DDL. B-tree, hash, GIN, and BRIN index types are recognized.

Limitations: the parser handles the three SQL dialects listed but is not a full grammar — exotic constructs like Postgres parallel-aware nodes or MySQL's `EXPLAIN FORMAT=TREE` partial outputs may render with `(unknown operator)` placeholders. The Mermaid output uses `graph TD` with cost-weighted edge thickness, which renders correctly on GitHub but not in older Confluence versions. Related skills: `sql:format` for query pretty-printing, `pg:slow-query-log` for finding candidates, `sql:index-advisor` for whole-schema index recommendations.
