---
title: "rebase conflict resolution toolkit"
created: 2026-03-01
last_used: 2026-05-15
last_validated: 2026-05-10
use_count: 14
provenance:
  - source: hand-authored
promote_when:
  use_count_min: 20
demote_when:
  days_since_last_use_min: 90
depends_on: []
status_history:
  - { tier: 0, at: 2026-03-01, reason: "born" }
  - { tier: 3, at: 2026-05-10, reason: "promoted twice" }
---

Workflow when a rebase hits a conflict:

1. `git status` — see the conflicted files.
2. Resolve. Use `git rerere` to memoize the resolution so a future
   re-run picks it up automatically.
3. `git add <files>` then `git rebase --continue`.
4. If a single hunk should be dropped: `git rebase --skip`.
5. If the whole rebase should be abandoned: `git rebase --abort` —
   the branch returns to `ORIG_HEAD`.

Related: `git:reflog-archaeology` for recovery if `--abort` happened
after data loss.
