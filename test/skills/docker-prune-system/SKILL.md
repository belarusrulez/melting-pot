---
name: docker:prune-system
description: Use WHEN docker is eating disk — reclaim space from dangling images, stopped containers, unused volumes, and build cache without nuking what you still need.
---

> Test fixture for sc:search search system.

`docker system prune -a --volumes` is the nuclear option and it WILL delete the volume holding your local Postgres data if you're not paying attention. This skill is the gentler, scoped path: show what would be reclaimed first, prune by category, and protect named/labeled volumes.

Reclaim flow:

```
docker system df                                          # what's using how much
docker image prune                                        # dangling images only
docker image prune -a --filter "until=168h"               # untagged + older than 7d
docker container prune --filter "status=exited"           # stopped containers
docker builder prune --keep-storage 10GB                  # leave 10G of build cache
docker volume ls -qf dangling=true                        # preview unused volumes
docker volume prune --filter "label!=keep"                # spare anything labeled keep
```

`docker system df -v` gives the line-by-line breakdown so you can see which image or volume is the actual whale. `--keep-storage` on the builder is the sane default for dev machines — keeps the most-recently-used layers and only evicts older ones.

Do NOT run `docker system prune -a --volumes -f` blindly in shared dev environments — it will obliterate teammates' volumes if you share a daemon. For BuildKit-specific cache see also `docker:build-cache`. Related: `disk:usage-top` for OS-level disk audits, `k8s:debug-pod` for in-cluster image-pull issues.
