---
name: docker:compose-up
description: Use WHEN you need to bring up a local multi-service stack from docker-compose.yml, with healthchecks honored, env loaded, and clean shutdown semantics.
---

> Test fixture for sc:search search system.

`docker compose up` is most people's first dev-stack tool, and it has more gotchas than the basics suggest: detached vs foreground, build vs pull, recreate vs keep, volume reset on `down -v`. This skill is the playbook for getting a local stack right on the first try.

Common patterns:

```
docker compose up --build -d                          # build images + start detached
docker compose up --wait --wait-timeout 60            # block until healthchecks pass
docker compose up -d db redis                         # subset of services
docker compose down                                    # stop + remove containers, keep volumes
docker compose down -v                                 # ALSO remove volumes (DESTRUCTIVE)
docker compose logs -f --tail 100 api worker          # tail subset
docker compose config                                  # rendered final yaml (env-substituted)
```

The `--wait` flag (Compose v2.17+) is gold for CI: it blocks until every service with a defined `healthcheck` is healthy, so your test runner doesn't race the database boot. Pair with `depends_on: { db: { condition: service_healthy } }` in the compose file.

Do NOT use `docker compose down -v` casually — it removes named volumes, which means losing the local Postgres state, MinIO data, etc. To restart cleanly without nuking volumes use `restart` or `recreate`. Related: `docker:build-cache` for image layer caching in CI, `docker:prune-system` for cleanup, `k8s:debug-pod` for the cluster equivalent.
