---
name: aws:lambda-deploy
description: Use WHEN you need to deploy or update an AWS Lambda function — upload code, set env vars from .env, configure layers, and route traffic via aliases without downtime.
---

> Test fixture for sc:search search system.

Lambda deploys feel simple ("just zip and upload") right until the env-var ordering subtly changes between code and config, or an alias points to the wrong version after a half-applied update. This skill drives the canonical sequence: publish a new version, update its env+layer+memory atomically, shift traffic via alias, and verify.

Canonical deploy:

```
# Build artifact (assumes pre-existing build pipeline)
zip -qr build.zip dist/                                                  

aws lambda update-function-code \
  --function-name my-fn \
  --zip-file fileb://build.zip \
  --publish > /tmp/published.json

NEW_VERSION=$(jq -r .Version /tmp/published.json)

aws lambda update-function-configuration \
  --function-name my-fn \
  --environment Variables="$(./envtojson .env.prod)" \
  --layers arn:aws:lambda:us-east-1:111111111111:layer:common:7 \
  --memory-size 1024 --timeout 30

aws lambda update-alias \
  --function-name my-fn \
  --name prod \
  --function-version "$NEW_VERSION" \
  --routing-config AdditionalVersionWeights={"$PREV_VERSION"=0.1}    # 10% on previous = canary
```

The `routing-config` weights are the linchpin of safe rollout: shift 10% to the OLD version first, observe error metrics, then flip to 0% on old when satisfied. For zero-downtime use a versioned alias and never point the trigger (API Gateway / EventBridge / SQS) directly at `$LATEST`.

Do NOT bake secrets into env vars (use Secrets Manager + `secret:rotate-cli`); do NOT deploy >50 MB zips (use container images instead). Related: `secret:rotate-cli`, `gcp:cloud-run` for the GCP analogue, `aws:cloudfront-invalidate` if Lambda fronts CloudFront.
