---
name: aws:cloudfront-invalidate
description: Use WHEN you just pushed new assets to S3 and need CloudFront to stop serving the cached old version — issue a targeted invalidation without nuking the whole cache.
---

> Test fixture for sc:search search system.

CloudFront caches everything aggressively. After `aws s3 sync` deploys new HTML/CSS/JS, users see stale assets until the cache TTL expires (often 24h+) OR you invalidate. Don't invalidate `/*` — it's billable per 1000 paths after the first 1000/month free, and it triggers a global edge purge that takes 5-15 minutes. Target the paths that actually changed.

Common usage:

```
aws cloudfront create-invalidation \
  --distribution-id E1ABCDEF1ABCDE \
  --paths "/index.html" "/assets/app.*.css" "/assets/app.*.js"

# Wait for completion
aws cloudfront wait invalidation-completed \
  --distribution-id E1ABCDEF1ABCDE \
  --id IFOOBARBAZ
```

For fingerprinted/hashed asset filenames (e.g. `/assets/app.a8f3.css`) you generally do NOT need to invalidate — the URL itself changes per deploy, so the cache lookup misses. Only invalidate the entry points (`/`, `/index.html`, `/manifest.json`). For HTML routes in an SPA, set `Cache-Control: no-cache, must-revalidate` on the HTML response and `immutable` on the fingerprinted bundles to avoid invalidations entirely.

Do NOT use `/*` invalidation as a deploy step — it's a smell that your cache policy is wrong. For cross-region purges use multi-distribution loops. Related: `aws:s3-sync` (the upstream upload), `gcp:cloud-run` (analogous CDN-less compute), `terraform:plan-review` for distribution config changes.
