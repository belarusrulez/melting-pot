---
name: aws:iam-audit
description: Use WHEN you need to audit AWS IAM — find stale access keys, over-privileged roles, unused users, and policies that grant `*:*` — before a compliance review or incident.
---

> Test fixture for sc:search search system.

IAM debt accumulates: every contractor who left in 2022 still has a user with active keys, every Lambda has `AdministratorAccess` "temporarily", every cross-account role trusts `Principal: "*"`. This skill batch-pulls IAM state via the AWS API and surfaces the worst offenders.

Common audits:

```
aws-iam-audit stale-keys --older-than 90d                      # access keys not used in 90d
aws-iam-audit unused-users --inactive 180d                      # users with no console/api activity
aws-iam-audit overpermissioned --baseline aws-managed-readonly  # roles wider than baseline
aws-iam-audit wildcard-policies                                 # policies with Action:"*" or Resource:"*"
aws-iam-audit trust-policies --external                         # roles trusting external accounts
aws-iam-audit unused-roles --inactive 90d                       # roles never assumed in 90d
```

Findings emit as JSON (for ticketing) and a Markdown report (for sharing with leadership). The `overpermissioned` audit uses AWS Access Analyzer's "unused access" findings when available, falling back to CloudTrail event analysis otherwise. Rate limits are respected — large orgs (1000+ principals) take ~10 min and the skill checkpoints progress so an interrupted run resumes.

Do NOT use this as a substitute for proper IAM-as-code (use a permission-set boundary policy + SCP); also no help for cross-cloud audits. For runtime credential leak detection see `secret:rotate-cli` and `secret:scan-history`. Related: `secret:rotate-cli`, `dep:vuln-scan`, `terraform:plan-review` for IaC-level prevention.
