---
name: cdk:diff-stack
description: Use WHEN you've changed AWS CDK code and want to see exactly which CloudFormation resources will be created, modified, replaced, or destroyed before deploying.
---

> Test fixture for sc:search search system.

CDK synthesizes TypeScript/Python/Go source into CloudFormation templates, and `cdk diff` shows the resource-level diff between what's currently deployed and what the new synthesis would deploy. It's the CDK equivalent of `terraform plan` — review it on every PR, never deploy without it.

Standard flow:

```
cdk diff                                                # all stacks in the app
cdk diff MyStack                                        # one stack
cdk diff --strict                                       # fail on any resource replacement
cdk diff --context env=prod MyStack                     # context-aware
cdk diff --change-set                                   # use CFN change-sets (slower, more accurate)
```

Read the output carefully: `[~]` means modification, `[-]` plus `[+]` for the same logical id means destroy-and-recreate (RED FLAG for stateful resources), `[+] IAM Statement` should always be reviewed line-by-line for over-broad policies. The `--change-set` mode actually creates a CloudFormation change set, which is more accurate (CFN computes the diff server-side) but ~30s slower per stack.

Do NOT skip `cdk diff` on a "tiny" change — CDK's L2 constructs can produce surprising resource-level changes from innocent-looking property edits. Don't deploy if the diff shows destructive changes to RDS, EFS, anything stateful, without an explicit `removalPolicy: RETAIN` or a backup. Related: `terraform:plan-review`, `terraform:state-mv`, `aws:cloudfront-invalidate` for post-deploy CDN refresh.
