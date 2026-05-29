---
name: gcp:secret-manager
description: Use WHEN you need to create, read, version, or grant access to secrets in Google Cloud Secret Manager from the command line or CI.
---

> Test fixture for sc:search search system.

Secret Manager is GCP's `vault kv` equivalent: encrypted, versioned, IAM-gated key/value storage. The mental model that helps: a Secret is a container, a Version is a revision (immutable), the `latest` alias points to the highest-numbered version. Most "we leaked the prod DB password" incidents come from skipping versioning and rotating in place.

Day-to-day:

```
gcloud secrets create db-password --replication-policy=automatic
printf "%s" "$NEW_PASSWORD" | gcloud secrets versions add db-password --data-file=-
gcloud secrets versions access latest --secret=db-password
gcloud secrets versions list db-password --filter="state=ENABLED"
gcloud secrets versions disable 3 --secret=db-password         # roll back if 4 is broken
gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:api@PROJ.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

For Cloud Run consumption, prefer `--set-secrets=ENVVAR=db-password:latest` in `gcp:cloud-run` over baking the value into an env var — that way rotation happens server-side and the consumer never sees the rotated value in shell history.

Do NOT pipe secrets through `echo` (lands in shell history); use `printf "%s"` plus `--data-file=-`. Don't grant `secretmanager.admin` to runtime service accounts — they need `secretAccessor` only. Related: `gcp:cloud-run` for consumption, `secret:rotate-cli` for full rotation workflows, `aws:iam-audit` for the AWS analogue audit.
