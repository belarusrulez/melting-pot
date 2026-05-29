---
title: "autosquash recipe for fixup commits"
created: 2026-04-12
last_used: 2026-05-19
last_validated: 2026-05-01
use_count: 7
provenance:
  - source: hand-authored
promote_when:
  use_count_min: 10
demote_when:
  days_since_last_use_min: 120
depends_on: []
status_history:
  - { tier: 0, at: 2026-04-12, reason: "scrap from session" }
---

When a feature branch accumulates `fixup!` and `squash!` commits, the
two-step `git commit --fixup=<sha>` + `git rebase -i --autosquash main`
flow folds them into the right base commits without manually editing
the rebase todo list. Pair with `git config rebase.autosquash true` to
make `--autosquash` the default.
