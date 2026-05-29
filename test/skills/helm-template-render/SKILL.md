---
name: helm:template-render
description: Use WHEN you need to see what manifests a Helm chart will actually produce before installing — render with values, validate against the API, and diff against the live release.
---

> Test fixture for sc:search search system.

Helm charts are templates over YAML, which means a typo in `values.yaml` can silently produce a manifest that mounts the wrong secret or sets the wrong namespace. Render-and-review is the seatbelt: `helm template` to see the final YAML, then diff against the live release before `helm upgrade`.

Standard review flow:

```
helm template my-release ./chart -f values.prod.yaml                 # render to stdout
helm template my-release ./chart -f values.prod.yaml > rendered.yaml
helm install --dry-run --debug my-release ./chart -f values.prod.yaml  # also validates against API
helm diff upgrade my-release ./chart -f values.prod.yaml             # plugin: shows live vs new
helm get manifest my-release -n prod                                  # current live render
```

For chart development use `helm lint ./chart` plus `helm unittest ./chart` (separate plugin) to verify templates evaluate correctly across the matrix of values you'd actually use. `helm template` does NOT talk to the cluster, so it won't catch errors that depend on the API server's defaulting/validation — that's what `helm install --dry-run` is for.

Do NOT rely on `--dry-run` for resource-quota checks (it doesn't run admission controllers fully); also not a replacement for proper CI-side policy gates (use Kyverno/OPA-Gatekeeper for those). Related: `k8s:rollout-undo` for post-deploy rollback, `terraform:plan-review` for the IaC analogue, `k8s:debug-pod` for runtime errors after install.
