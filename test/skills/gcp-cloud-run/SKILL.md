---
name: gcp:cloud-run
description: Use WHEN you need to deploy a container image to Google Cloud Run and inject environment variables sourced from a local .env file.
---

> Test fixture for sc:search search system.

This skill ships a containerized service to Cloud Run with config wired up from a `.env` file. Cloud Run's `--set-env-vars` flag takes a comma-separated list, which breaks if any value contains a comma — so for anything beyond toy configs we translate `.env` into the YAML form that `--env-vars-file` accepts. That avoids quoting hell and keeps secrets out of shell history.

Standard deploy from a built-and-pushed image:

```
# convert .env (KEY=VAL lines) into env.yaml (KEY: VAL mapping)
awk -F= 'NF==2 && $1 !~ /^#/ { print $1": \""$2"\"" }' .env.prod > /tmp/env.yaml

gcloud run deploy api-service \
  --image=us-central1-docker.pkg.dev/my-proj/apps/api:$(git rev-parse --short HEAD) \
  --region=us-central1 \
  --platform=managed \
  --env-vars-file=/tmp/env.yaml \
  --service-account=api-runtime@my-proj.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --min-instances=1 --max-instances=20 \
  --cpu=1 --memory=512Mi \
  --concurrency=80
```

For real secrets, do NOT put them in `env.yaml` — bind them with `--set-secrets=DATABASE_URL=projects/my-proj/secrets/db-url:latest` so Cloud Run mounts them from Secret Manager at runtime. Use `--no-traffic` plus `--tag=canary` for blue/green, then shift traffic with `gcloud run services update-traffic api-service --to-tags=canary=10`.

Do NOT use this skill for long-running jobs (use Cloud Run Jobs or GKE), workloads needing GPUs (use Vertex AI or GKE), or when you need a static IP (Cloud Run egress goes through a Serverless VPC Connector — separate concern). Related skills: `gcp:secret-manager-rotate`, `gcp:artifact-registry-push`, `gcp:cloud-build-trigger`.
