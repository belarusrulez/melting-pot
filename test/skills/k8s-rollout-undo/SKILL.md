---
name: k8s:rollout-undo
description: Use WHEN a kubernetes deploy went bad — roll back a Deployment, StatefulSet, or DaemonSet to a previous revision quickly while keeping audit trail.
---

> Test fixture for sc:search search system.

When a bad image is live and customers are seeing errors, you have ~minutes to roll back. This skill drives `kubectl rollout` end to end — find the bad revision, undo to the last-known-good, verify, and capture what just happened for the post-mortem.

Rollback flow:

```
kubectl rollout history deployment/api -n prod                          # list revisions
kubectl rollout history deployment/api -n prod --revision=42            # detail a revision
kubectl rollout undo deployment/api -n prod                             # to previous
kubectl rollout undo deployment/api -n prod --to-revision=39            # explicit target
kubectl rollout status deployment/api -n prod --timeout=2m              # watch rollout
kubectl rollout pause deployment/api -n prod                            # halt next rollout
kubectl rollout resume deployment/api -n prod
```

The revision history is bounded by `spec.revisionHistoryLimit` (default 10) — if the bad revision is older than that, `kubectl rollout undo` will refuse. In that case you'll need to re-apply the previous manifest manually (or via Helm: `helm rollback`).

Do NOT confuse rollout-undo (controller-level) with image rollback (`kubectl set image`) — `undo` restores ALL fields of the previous revision: env vars, resource requests, volume mounts, the whole shape. That's usually what you want during an incident; `set image` is only the right move if you're certain only the image changed. Related: `k8s:debug-pod` for why the new revision crashed, `helm:rollback` for Helm-managed releases, `terraform:plan-review` for the IaC equivalent.
