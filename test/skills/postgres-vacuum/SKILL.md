---
name: postgres:vacuum
description: Use WHEN postgres performance is degrading from table bloat or you've just done a large delete/update — run VACUUM, ANALYZE, and surface tables that need attention.
---

> Test fixture for sc:search search system.

Postgres's MVCC keeps old row versions until VACUUM reclaims them. Heavy update/delete workloads bloat tables and indexes, query plans go stale, and slowly the whole database feels sluggish. This skill drives the right blend of VACUUM/ANALYZE based on what the current state looks like.

Triage queries:

```sql
-- which tables are bloated
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / NULLIF(n_live_tup,0) * 100, 1) AS pct_dead
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY pct_dead DESC LIMIT 20;

-- when was each table last (auto)vacuumed
SELECT relname, last_vacuum, last_autovacuum, last_analyze
FROM pg_stat_user_tables ORDER BY last_autovacuum NULLS FIRST LIMIT 20;
```

Then act:

```sql
VACUUM (VERBOSE, ANALYZE) public.events;                      -- regular vacuum
VACUUM (FULL, VERBOSE) public.events;                          -- reclaims disk, LOCKS table
REINDEX TABLE CONCURRENTLY public.events;                      -- index bloat fix, no lock
ANALYZE public.events;                                          -- update planner stats only
```

`VACUUM FULL` rewrites the table and **takes an exclusive lock** — never run it on a live OLTP table without a maintenance window. `pg_repack` is the right answer for online table rewrite. Autovacuum tuning per-table via `ALTER TABLE ... SET (autovacuum_vacuum_scale_factor = 0.01)` is the right long-term fix for hot tables that bloat faster than the global setting can keep up with.

Do NOT confuse VACUUM with backups (it doesn't free OS-level disk except for FULL); also not a substitute for proper index hygiene. Related: `sql:explain` for plan-staleness symptoms, `db:migrate-up` (post-migration is a common bloat trigger), `loki:logql-query` for vacuum logs.
