# melting-pot — final synthesis report

> Team `melting-pot-v5-build` · build commit pending user approval · 97/97 tests green · zero critic findings

## 1. TL;DR

Team has shipped a complete v1 implementation of melting-pot — the vendor-neutral, six-tier, overlay-and-patches skill store described in `plans/migration_v5_pm.md` — at `/Users/coding/Projects/melting-pot/`. Seven of nine planned phases are done (Phases 0–7); Phase 8 was the critic+report cycle (you are reading the report). Phase 9 (cutover from `sc/*` to `mp/*` in your actual harness config) is deferred per the plan and awaits your sign-off. Nothing has been committed or pushed — the team respected your global "never commit/push without explicit permission" rule. Next: skim `plans/architecture.md` and `plans/build_order.md`, then decide whether to commit and whether to run `install/install.sh` in a sandboxed environment.

## 2. The plan

Three plan files at `/Users/coding/Projects/melting-pot/plans/` are the canonical record: `architecture.md` (hub diagram + component contracts + invariants), `build_order.md` (nine phases, cherry-pick map from `sc/`, dependency graph), and `open_questions.md` (Q-IDs with full audit trail). Phases 0–7 were implementation; Phase 8 was critic+report; Phase 9 is the deferred cutover. Seven user decisions (Q-001, Q-003, Q-007, Q-008, Q-012, Q-013, Q-014) shaped the contracts before code was written. Eight questions remain open (Q-002, Q-004, Q-005, Q-006, Q-009, Q-010, Q-011, Q-015), all with v1 defaults already coded.

## 3. What shipped — by phase

| Phase | Scope | Primary files (lines) | Tests | Notes |
| --- | --- | --- | --- | --- |
| **0 — Plan** | 3 plan files; 7 Q-IDs resolved | `plans/architecture.md`, `plans/build_order.md`, `plans/open_questions.md` | n/a | All status `[x]` |
| **1 — Shared library** | 4 lib scripts + smoke tests | `mp/lib/discover.sh` (381), `mp/lib/tier.sh` (363), `mp/lib/patch.sh` (284), `mp/lib/compose.sh` (389) | LIB-* | discover unions reg+overlay and symlinks upstream `N-melting-pot/`; patch is policy-free with `.failed/` markers |
| **2 — mp:search** | FTS5 + RRF, tier-aware reindex | `mp/search/action` (661), `mp/search/SKILL.md` | PHASE2-SRCH-* | RRF block lifted verbatim from sc:search |
| **3 — mp:list + mp:crud** | Inventory + lifecycle helpers | `mp/list/action` (319), `mp/crud/action` (641) | PHASE3-LIST-*, PHASE3-CRUD-* | crud adds `patch-add` / `patch-list` / `patch-validate` / `patch-remove` |
| **4 — mp:load** | Compose whole skill | `mp/load/action` (161), `mp/lib/compose.sh` | PHASE4-LOAD-* | Thin CLI; markdown default, JSON via `--format json` |
| **5 — mp:learn** | Largest new unit | `mp/learn/action` (872), `mp/learn/SKILL.md` | PHASE5-LEARN-* (16) | `promote` / `demote` / `cleanup` / `refactor` / `cascade` / `harvest` / `harvest --transcript` / `eval` / `patch-triage` |
| **6 — Hooks + installer** | Harness-agnostic | `install/install.sh` (324), `melt-nudge.sh` (85), `melt-resume.sh` (75), `REGISTER-HOOKS.md`, `task-intake.md` | PHASE6-IN-01..08 | Never mutates `~/.claude/settings.json`; emits markdown manifest |
| **7 — Test corpus** | 79 fixtures + golden rubric | `test/skills/` (79 dirs), `test/golden/RUBRIC.md`, `test/golden/queries.tsv`, `test/run-tests.sh` | PHASE7-CORPUS-01..04 | 78 carried verbatim from skill-core; +1 native `melting-pot-native-demo` fixture |

Total: ~7,118 lines of implementation; 97 tests, 0 failures, 0 skips.

## 4. Cherry-picks from skill-core

### Lifted verbatim (~60%)
- `sc/lib/discover.sh` — `sc_warn`, `sc_err`, `sc_sql_esc`, `sc_expand_root`, `sc_parse_patterns`, `sc_fm_field`, `sc_body_after_fm`, `sc_has_frontmatter`, `sc_name_from_dirname`, `sc_json_escape`
- `sc/search/action` — `sc_resolve`, `escape_fts_q`, atomic reindex (`index.db.tmp` → `mv`), hash-gated drift skip, the entire RRF SQL block (`bm25(skills,10,8,5,4)` + top-5 cap + `SUM(1.0/(10.0+rnk))`), `cmd_doctor`
- `sc/crud/action` — `cmd_collision_check`, `cmd_validate` shape, `cmd_trash`, `cmd_restore`, `cmd_import_preview`
- `sc/list/action` — output shape and discover-union loop
- `test/run-tests.sh` harness (`t_setup`, assertion helpers, sandboxed `$SC_HOME`→`$MP_HOME`)
- `test/golden/RUBRIC.md` unchanged; `test/golden/queries.tsv` 39 graded rows reused as-is

### Adapted (~25%)
- `mp_discover_skills` unions reg + overlay and symlinks upstream tier dirs (Q-007)
- `cmd_reindex` walks `N-melting-pot/` tiers, applies patches in-memory before indexing, records failures to `.failed/`
- `mp_compute_skills_hash` extended to cover chunks + patches + `.failed/` markers + meta.md + symlink targets
- `cmd_search` text output adds `origin=` / `avg_tier=` / `hits=[…]` / `patches=N applied [failed=M]`
- `cmd_scaffold` defaults to native six-tier; `--legacy` flag preserves `SKILL.md` shape
- `cmd_validate` adds `N-melting-pot/` naming + frontmatter + patch parse + `.failed/` envelope checks
- `mp/list/action` rows gain `origin` / `tiers_present` / `chunk_count` / `patches_count` / `patches_failed_count`

### Authored fresh (~15%)
- `mp/lib/tier.sh` (363) — `walk_tier_dirs`, `resolve_chunk_path`, `append_status_history` (idempotent per Q-014), `read_tier_meta`, `detect_full_overlay_mode`
- `mp/lib/patch.sh` (284) — policy-free apply pipeline + `.failed/` markers (Q-001)
- `mp/lib/compose.sh` (389) — `compose_skill` for `mp:load`
- `mp/load/action` (161) + SKILL.md — new skill
- `mp/learn/action` (872) + SKILL.md — largest new unit; all lifecycle scripts + `patch-triage` (Q-001)
- `mp/crud/action` patch-* subcommands
- `install/install.sh` (324) — bundled installer (Q-013), markdown-only manifest (Q-012), never mutates harness config (Q-003)
- `install/hooks/melt-nudge.sh` (85), `install/hooks/melt-resume.sh` (75) — harness-agnostic POSIX sh
- `install/REGISTER-HOOKS.md`, `install/task-intake.md` — emitted templates
- Chunk frontmatter schema (title / created / last_used / last_validated / use_count / provenance / promote_when / demote_when / depends_on / status_history)

## 5. Resolved invariants (7 Qs) — verbatim user rationale

- **Q-001** Patch pipeline is policy-free; failures recorded as `.failed/` markers; LLM-mediated triage. *"when patch is not working then we should note it inside skill directory (in our directory) and next time when we do learn we should find all this patches that don't apply and llm should figure out what to do with them on case by case basis"*
- **Q-003** Hooks + installer are harness-agnostic; installer never mutates harness config. *"llm should write for us. we just say register this scripts in clean session hook. it should be llm agnostic."*
- **Q-007** Tier dirs are `N-melting-pot/` (suffix mandatory); upstream tier dirs symlinked into overlay; full-overlay mode when upstream has any of them. *"let's call our dirs 0|1|2-melting-pot if their repo has it then use them (it means they should be 'our' structure) we should ln them to our dir so our search system will not break. and if it has 0,1,2,3, and not 4,5 then use our system entirely."*
- **Q-008** Clean fork to `~/.melt/repos.patterns`; no runtime fallback. *"Clean fork to `~/.melt/repos.patterns`"*
- **Q-012** Installer emits markdown-only manifest. *"Markdown only"*
- **Q-013** Single `install/install.sh` bundles hook manifest + task-intake emit. *"Bundle — single `install/install.sh`"*
- **Q-014** `mp_append_status_history` is idempotent on `(chunk, tier, reason, timestamp)`. Closed as fixed-in-code with regression test.

## 6. Open questions (8 Qs, all with v1 defaults)

- **Q-002** Tier-cascade on dep demotion — v1: **flag-only** (`mp:learn cascade` marks; never auto-mutates). Low stakes.
- **Q-004** `use_count` write path — v1: **load-time write** only (`mp:load` increments; `mp:search` doesn't). Avoids read-path contention.
- **Q-005** `promote_when`/`demote_when` grammar — v1: **structured-key schema** (no DSL). **Highest stakes** — DSL from the pitch needs a small awk evaluator if you want it.
- **Q-006** `mp:learn harvest` provenance — v1: **agent pipes JSON to stdin** in live-context mode; transcript mode reads `.jsonl`. **Second-highest stakes** — JSON shape may evolve.
- **Q-009** Tier ceiling/floor — v1: **full mobility** (no floor, no ceiling).
- **Q-010** Hook nudge throttle — v1: **per-session** (per the pitch). Low stakes.
- **Q-011** `.failed/` marker schema — v1: **single file with delimited sections**. Already shipped + tested.
- **Q-015** `mp:learn refactor` near-duplicate detection — v1: **title-only matching**. FTS5 NEAR deferred.

Recommendation: revisit Q-005 + Q-006 before long-lived chunk frontmatter accumulates (changing them later requires migration). The rest are tuning knobs.

## 7. How to use it

```sh
cd /Users/coding/Projects/melting-pot

# 1. Verify all tests green (expect 97/97)
sh test/run-tests.sh

# 2. See what the installer would do (no writes)
sh install/install.sh --dry-run

# 3. Actually install (creates ~/.melt/, copies hooks, emits manifest)
sh install/install.sh

# 4. Hand the manifest at ~/.melt/REGISTER-HOOKS.md to the LLM agent
#    so it registers the hooks in your harness config.
#    Read it yourself first before any LLM acts on it.

# 5. Seed ~/.melt/repos.patterns with skill-core defaults
sh mp/search/action doctor --write-sample

# 6. Confirm fixture discovery works
sh mp/list/action --count

# 7. Three-axis search smoke test
sh mp/search/action search "rebase" "git history rewrite" "squash commits"

# 8. Compose a full skill (manifest + all tiers + patches)
sh mp/load/action git-rebase

# Optional one-time migration from sc
sh install/install.sh --copy-from-sc
```

## 8. What's NOT done

- **Phase 9 cutover** (deferred per build_order.md; you drive it).
- **No commits, no pushes** (global rule respected).
- **FTS5 NEAR-based refactor** (Q-015 deferred enhancement).
- **Eight open Q-IDs** — all have v1 defaults already coded; nothing blocks usage.

## 9. Next steps for the user

1. Read `plans/architecture.md`, `plans/build_order.md`, `plans/open_questions.md`, plus this report.
2. Decide on commits (team did not commit; explicit permission required).
3. Optionally answer remaining 8 open Qs or accept v1 defaults.
4. Sandbox-install first: `install/install.sh --dry-run` → `install/install.sh` → review `~/.melt/REGISTER-HOOKS.md` by hand before any LLM acts on it.
5. Phase 9 cutover when confident (swap `sc:*` → `mp:*` in `~/.claude/skills/` or equivalent).
