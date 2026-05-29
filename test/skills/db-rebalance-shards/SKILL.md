---
name: db:rebalance-shards
description: Use WHEN a sharded database has uneven load — one shard handling 80% of traffic — and you need to plan and execute a shard rebalance with minimal downtime.
---

> Test fixture for sc:search search system.

Sharded databases drift: a single tenant grows, a hash function distributes unevenly, an availability zone fills first. This skill drives the rebalance: profile current shard sizes, plan target distribution, copy ranges to new shards, cut over consumers, and decommission the old.

Workflow (Vitess-style; adapts to Citus, CockroachDB, MongoDB):

```
db-rebalance-shards inspect --cluster prod                # current load + size per shard
db-rebalance-shards plan --target balanced > plan.yaml    # plan the moves
db-rebalance-shards apply --plan plan.yaml --rate 50MB/s  # copy with throttling
db-rebalance-shards switch --plan plan.yaml               # atomically flip reads
db-rebalance-shards verify --plan plan.yaml               # row-count match
db-rebalance-shards cleanup --plan plan.yaml              # drop old ranges
```

The cutover is the only non-idempotent step — everything before is safe to re-run. The `--rate` flag throttles cross-shard copying so you don't saturate the network during business hours; typical production runs do 20-50 MB/s and complete overnight.

Do NOT use this skill for `git rebase` workflows — completely different operation despite the name overlap. Don't rebalance during a deploy window; do it during low-traffic hours with on-call coverage. Related: `postgres:vacuum`, `db:migrate-up`, `terraform:plan-review` if shard topology lives in IaC.
