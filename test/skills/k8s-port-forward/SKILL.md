---
name: k8s:port-forward
description: Use WHEN you need to reach a service inside a kubernetes cluster from your laptop — port-forward to a Pod, Service, or Deployment, with auto-restart on disconnect.
---

> Test fixture for sc:search search system.

`kubectl port-forward` is the quick path to talking to an in-cluster service without exposing it via Ingress. The connection drops on every API server hiccup, every laptop sleep, every network blip — so wrap it in a restart loop for anything other than a 30-second probe.

Common invocations:

```
kubectl port-forward svc/api 8080:80 -n prod                         # local 8080 → service port 80
kubectl port-forward deploy/api 8080:8080 -n prod                    # forward to current pod of deploy
kubectl port-forward pod/api-7d4-x9k 5005:5005 -n prod               # specific pod (for debuggers)
kubectl port-forward svc/postgres 5432:5432 -n data --address 0.0.0.0  # listen on all interfaces
# Auto-restart wrapper:
while true; do kubectl port-forward svc/api 8080:80 -n prod; sleep 1; done
```

Two pitfalls: `--address 0.0.0.0` listens on every interface and is a security hole on a coffee-shop wifi. And port-forward routes traffic to *one* pod (random for `svc` and `deploy`), so a "1 in 5 requests fails" test won't reproduce the same way as production load-balanced traffic — for that use `kubectl proxy` plus the Service IP, or stand up a real LB.

Do NOT use port-forward as a permanent ingress (use Ingress/Gateway API); also no help for cluster-to-laptop direction (use `kubectl exec` or a reverse tunnel). Related: `k8s:debug-pod`, `k8s:rollout-undo`, `kubectl:exec-into-pod`.
