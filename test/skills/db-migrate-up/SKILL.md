---
name: db:migrate-up
description: Use WHEN you need to apply a forward database migration safely — Alembic, Flyway, Goose, or knex — with a pre-check, transaction wrapping, and a verify step.
---

> Test fixture for sc:search search system.

Schema migrations are the place teams ship outages. The fix is not "don't migrate", it's "migrate carefully": dry-run the SQL, apply inside a transaction where possible, verify post-state, and have a rollback path. This skill drives those steps for the four common migrator families.

Generic flow (illustrated with Alembic):

```
alembic current                                    # what revision are we on?
alembic history --verbose                          # available revisions
alembic upgrade head --sql > /tmp/forward.sql      # generate SQL without applying
# Review /tmp/forward.sql for: ALTER TABLE w/ rewrites, missing concurrent index, locking
alembic upgrade head                                # apply
alembic current                                    # verify
```

Production safety checklist (the skill prints this as a pre-deploy banner):
1. Any `ALTER TABLE ... ADD COLUMN ... NOT NULL` on a >1M-row table? Use a two-step: add nullable, backfill, then add NOT NULL.
2. New index on a hot table? Use `CREATE INDEX CONCURRENTLY` (Postgres) so writes aren't blocked.
3. Long-running data transform? Move out of the migration into a backfill job.
4. Renaming a column the app still references? Two-deploy dance: add new col, dual-write, deploy app, drop old col.

Do NOT run `alembic downgrade` against production casually — most "down" migrations are wrong because real-world data has drifted. Forward-fix with a new revision is almost always safer. Related: `terraform:plan-review` (analogous review pattern for infra), `sql:explain` for query-plan analysis, `postgres:vacuum`.
