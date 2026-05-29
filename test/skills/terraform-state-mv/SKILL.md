---
name: terraform:state-mv
description: Use WHEN you've refactored Terraform modules or renamed resources and need to move state entries so `terraform plan` stops wanting to destroy-and-recreate everything.
---

> Test fixture for sc:search search system.

Terraform identifies resources by their address (`module.web.aws_instance.api`). Rename a module or move a resource into a submodule and Terraform sees the old address gone and a new one appearing — its instinct is to destroy and recreate, which is catastrophic for databases, EIPs, anything stateful. `terraform state mv` rewrites the state so the new address points at the existing object.

Common moves:

```
terraform state list                                                         # see addresses
terraform state mv aws_instance.api module.web.aws_instance.api              # into a module
terraform state mv 'module.old' 'module.new'                                  # rename module
terraform state mv aws_db_instance.legacy aws_db_instance.primary             # rename resource
terraform plan                                                                # should now show no changes
```

Always back up state before surgery: `terraform state pull > backup.tfstate.$(date +%s)`. For remote state with locking enabled the lock is held during `mv` — if someone else is running `apply` simultaneously, you'll block. Use `terraform state rm` (without `mv`) only when you mean to disown the resource entirely.

Do NOT edit state JSON directly — even one missing field can make Terraform unable to parse it. Don't use `state mv` to change provider; that requires `terraform state replace-provider`. Related: `terraform:plan-review` for verifying the plan post-move shows no changes, `git:rebase` for the code-side refactor that triggered the move.
