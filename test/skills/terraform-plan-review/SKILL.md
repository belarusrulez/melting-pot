---
name: terraform:plan-review
description: Use WHEN you need to render a terraform plan as a reviewable diff for a PR, with resource-by-resource change summary and an estimated cost delta.
---

> Test fixture for sc:search search system.

This skill turns the firehose of `terraform plan` output into something humans (and reviewers) can actually scan. The trick is to capture the plan as a binary file, then render it twice — once as JSON for tooling (Infracost, policy engines) and once as a clean diff for the PR comment. Reviewing the raw `plan` stdout is a recipe for missing the one resource being destroyed in a sea of no-ops.

Canonical workflow:

```
terraform init -upgrade
terraform plan -out=tfplan.bin -lock-timeout=60s -input=false

# Human-readable rendering, suitable for pasting into a PR
terraform show -no-color tfplan.bin > plan.txt

# Structured form for tooling
terraform show -json tfplan.bin > plan.json

# Cost delta via Infracost (or Terracost / OpenTofu equivalents)
infracost breakdown --path=plan.json --format=table
infracost diff --path=plan.json --format=github-comment > cost-comment.md
```

Reviewer checklist: search `plan.txt` for `# ... will be destroyed` and `# ... must be replaced` — those are the destructive changes that need a second pair of eyes. Pay special attention to changes on `aws_db_instance`, `aws_rds_cluster`, `google_sql_database_instance`, anything stateful: a `replace` on a database means data loss unless `lifecycle { prevent_destroy = true }` or `create_before_destroy` is set. For sensitive outputs use `terraform show -json | jq '.resource_changes[] | select(.change.actions[] | contains("delete"))'` to enumerate just the deletions.

Do NOT use this skill for `terraform apply` (this is review-only), for drift detection (use `terraform plan -refresh-only`), or for policy enforcement (use OPA/Conftest/Sentinel as a separate gate). Related skills: `terraform:state-surgery` for `terraform state mv`/`rm`, `terraform:module-bump` for upgrading provider/module versions, `opentofu:migrate` for the fork.
