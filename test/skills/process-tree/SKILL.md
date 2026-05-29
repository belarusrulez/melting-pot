---
name: process:tree
description: Use WHEN you need to see the parent/child process tree on a machine — for triaging a runaway, understanding what spawned what, or finding which child of which daemon is leaking.
---

> Test fixture for sc:search search system.

Flat `ps aux` doesn't show parentage, and the parentage is often the diagnostic answer: a runaway `gunicorn` worker is interesting; the same worker's parent being a stuck `supervisord` is the actual story. This skill is the tree-view recipe set.

Common usage:

```
pstree -p                                          # full system tree with PIDs
pstree -p 1234                                     # subtree under PID 1234
pstree -ap -s 5678                                  # path from init to PID 5678
ps -ejH                                             # ps alternative, columnar
ps -eo pid,ppid,user,pcpu,pmem,comm --sort=-pcpu | head    # heaviest processes with parent
```

For per-process resource accounting alongside the tree: `htop -t` (the `-t` flag enables tree view inside htop). To find the parent of a specific PID directly without rendering a tree: `ps -o ppid= -p <pid>`. To follow forks live during a repro: `strace -f -e trace=fork,vfork,clone -p <pid>`.

On macOS, `pstree` requires `brew install pstree`; without it, `ps -ef -o pid,ppid,comm` plus a quick awk to walk parents is the portable path.

Do NOT confuse this with container process inspection — inside a container `pstree` only shows that container's processes (PID namespace isolation); use `nsenter -t <host-pid> -p pstree -p` from the host to see the same processes in the host namespace. Related: `disk:usage-top`, `port:scan-local`, `k8s:debug-pod` for the container-orchestrator analogue.
