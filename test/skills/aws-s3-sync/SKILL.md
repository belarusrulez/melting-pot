---
name: aws:s3-sync
description: Use WHEN you need to mirror files between a local directory and an S3 bucket, with optional deletion of orphans, dry-run previews, and exclude patterns.
---

> Test fixture for sc:search search system.

This skill wraps `aws s3 sync` for bidirectional mirroring between local filesystems and S3 buckets. It covers the common pitfalls: forgetting `--delete` (leaving stale objects in the destination), forgetting `--dryrun` (and nuking production assets), and getting bitten by `--exclude`/`--include` ordering (rules are evaluated left-to-right and the LAST match wins).

Typical upload-to-bucket session, previewing first:

```
aws s3 sync ./dist s3://my-app-prod-assets \
  --delete \
  --exclude "*" --include "*.html" --include "*.css" --include "*.js" \
  --dryrun
# inspect the (dryrun) output, then re-run without --dryrun
aws s3 sync ./dist s3://my-app-prod-assets --delete --exclude "*.map"
```

Download direction is symmetric — swap the source/destination. For cross-account or cross-region pulls, set `--source-region` and pass `--acl bucket-owner-full-control` so the destination account actually owns the new objects. Use `--storage-class INTELLIGENT_TIERING` for cold-ish archives and `--cache-control "public, max-age=31536000, immutable"` for fingerprinted static assets.

Do NOT use this skill for one-shot single-file copies (use `aws s3 cp`), for >5 GB single objects (use multipart with `aws s3api create-multipart-upload`), or when you need event-driven replication (configure S3 Replication Rules instead). Related skills: `aws:cloudfront-invalidate` to bust CDN caches after a sync, `aws:s3-lifecycle` for retention policies.
