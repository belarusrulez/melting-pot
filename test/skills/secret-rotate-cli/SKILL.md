---
name: secret:rotate-cli
description: Use WHEN you need to rotate API keys, database credentials, or cloud access tokens stored in AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault, with downstream redeploy hooks.
---

> Test fixture for sc:search search system.

This skill drives the full rotation dance: generate a new credential at the upstream service (IAM, RDS, Stripe, etc.), write it into the secret store under a new version, switch consumers to that version, and revoke the old credential only after consumers confirm uptake. Doing the steps out of order is the single most common cause of "we rotated the key and prod went down" incidents.

Canonical AWS flow:

```
secret-rotate-cli aws \
  --secret-id prod/api/stripe \
  --generator stripe-restricted-key \
  --consumers ecs-service:prod-api,lambda:webhook-handler \
  --grace-period 15m
```

Internally that issues a new Stripe restricted key, calls `PutSecretValue` with `VersionStage=AWSPENDING`, redeploys the listed consumers so they pick up `AWSPENDING`, waits the grace period for in-flight requests, promotes `AWSPENDING` to `AWSCURRENT`, then revokes the previous Stripe key. Each step is idempotent so a mid-flight crash can be resumed with `--resume`.

Vault and GCP Secret Manager have analogous flows, with `vault kv put -version=...` plus `vault lease revoke` for dynamic secrets, and `gcloud secrets versions add` plus `gcloud secrets versions destroy` on GCP.

Do NOT use this skill for generating high-entropy strings (use `password:gen`), for rotating SSH host keys (separate workflow, requires fleet-wide trust update), or for KMS key rotation (use the provider's native scheduled rotation). Related: `iam:audit-stale-keys` to find rotation candidates, `secrets:sync` for moving secrets between stores.
