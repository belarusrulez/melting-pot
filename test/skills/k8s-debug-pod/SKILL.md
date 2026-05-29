---
name: k8s:debug-pod
description: Use WHEN a pod is stuck in CrashLoopBackOff, ImagePullBackOff, or OOMKilled and you need a systematic path through logs, events, exec, and ephemeral debug containers.
---

> Test fixture for sc:search search system.

This skill walks the standard Kubernetes triage tree for a misbehaving pod. The biggest mistake is jumping straight to `kubectl logs` — if the container never started, there are no logs, and the answer is in `kubectl describe` events (ImagePullBackOff, FailedScheduling, mount failures, init container errors).

Triage in this order:

```
# 1. What does the cluster THINK is wrong?
kubectl describe pod <pod> -n <ns> | tail -40    # Events section is gold

# 2. Logs from the last crashed container (not the currently-restarting one)
kubectl logs <pod> -n <ns> -c <container> --previous --tail=200

# 3. Watch the restart loop live
kubectl get pod <pod> -n <ns> -w

# 4. If the image is alive long enough, exec in
kubectl exec -it <pod> -n <ns> -c <container> -- sh

# 5. If the container has no shell (distroless/scratch), attach an ephemeral debug container
kubectl debug -it <pod> -n <ns> --image=busybox:1.36 --target=<container>
```

`OOMKilled` (exit code 137) means raise `resources.limits.memory` or fix the leak — confirm with `kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'`. `CrashLoopBackOff` with exit 1 is almost always app config: missing env var, unreachable database, bad migration. Check init containers separately — `kubectl logs <pod> -c <init-container>` — they run sequentially and a failure there blocks the main container from ever starting.

Do NOT use this skill for cluster-wide issues (use `kubectl get events -A --sort-by=.lastTimestamp`), node-level problems (SSH to the node, check kubelet/containerd), or networking (use `k8s:network-trace`). Related skills: `k8s:resource-tune` for limits/requests, `helm:rollback` for reverting a bad release, `k8s:rbac-audit` for permission denials.
