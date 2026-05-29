# melting-pot — open questions

> Architectural questions that surfaced during planning. Each has a Q-ID, a "Blocks" field (what it prevents from progressing), and the relevant context. Resolutions move to `## Resolved` with **Decision / Rationale / Landed in** fields. Nothing is deleted.

## Open

### Q-002 · Tier-cascade rule on dependency demotion
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** mp:learn cascade subcommand (Phase 5)
**Context:** Pitch: "If a dependency demotes, dependents may auto-demote too (cascade rule)." The "may" is doing a lot of work. Three plausible policies: (1) **auto-cascade** — demote dependent one tier down whenever a `depends_on` chunk demotes; (2) **flag-only** — never auto-mutate; mark dependents for review in `mp:learn cleanup` output; (3) **threshold** — auto-demote only if dependent's current tier is higher than dependency's new tier. v1 plan defaults to (2) flag-only to avoid surprising auto-mutation; confirm or override before Phase 5.

### Q-004 · `use_count` write path — does mp:search mutate chunks?
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** mp:search side-effects scope (Phase 2), mp:learn promote conditions (Phase 5)
**Context:** Pitch: "`mp:search` increments `use_count` on each hit." But mp:search runs on every query — incrementing a counter per chunk on every search is (a) write contention on the read path, (b) inflates counts for searches that don't actually use the skill. Two alternatives: (1) **search-time write** — increment when a skill ranks in convergence, accepting the noise; (2) **load-time write** — only `mp:load` increments (counts "actual reads", not "appeared in results"); (3) **harvest-time write** — `mp:learn harvest` is the only thing that ever touches chunk metadata. v1 plan defaults to (2) because it matches the "use" intent best; confirm before Phase 5 designs the promote rules.

### Q-005 · Expression grammar for `promote_when` / `demote_when`
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** mp:learn promote/demote/eval (Phase 5)
**Context:** Pitch shows `promote_when: "use_count >= 10 AND days_since_last_use <= 30 AND no_demote_signal"`. This is a DSL. The plan needs to either (a) implement a small expression evaluator in POSIX awk supporting `>=`/`<=`/`==`/`AND`/`OR` over a fixed variable set (`use_count`, `days_since_last_use`, `days_since_validated`, `tier`, `no_demote_signal`), or (b) restrict frontmatter to a structured schema with named keys (`promote_when.use_count_min`, `promote_when.days_since_last_use_max`, …) and skip a DSL entirely. Option (a) matches the pitch verbatim but is more code; option (b) is more rigid but unambiguous. v1 plan tilts toward (b) for portability; confirm or override. **NOTE post-Q-001 resolution:** the patch-failure flow now sends `.failed/` markers to `mp:learn` for LLM-mediated triage, which is a similar policy-via-LLM pattern. That doesn't directly answer Q-005, but it weakens the case for a runtime DSL — if the LLM is already the policy engine for failed-patch triage, the LLM can also handle ambiguous promote/demote calls, and the frontmatter rules can stay as structured key-value rather than a parsed expression. Tilt toward (b) strengthened.

### Q-006 · Provenance for `mp:learn harvest` — live context vs. transcript
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** mp:learn harvest (Phase 5), hooks (Phase 6)
**Context:** `mp:learn harvest` reflects on session content to propose new chunks. In **live-context mode** the agent (current conversation) is the only one with access to the relevant context — `mp:learn` is a shell script and can't read the agent's working memory. So the action probably needs to accept the proposal *from* the agent (the agent reads its own context, summarizes, pipes structured proposals into the action via stdin) rather than try to discover the techniques itself. In **transcript mode** the action *can* read the `.jsonl` directly. The two modes have very different I/O contracts. Confirm the live-context input format (probably: agent pipes a JSON document with proposed `{create|update|promote|demote}` actions to the action; action validates and applies).

### Q-009 · Are user-owned overlay chunks ever moved to tier 5?
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** mp:learn promote rules (Phase 5)
**Context:** The pitch says "every new chunk starts at tier 0" — true. But once promoted to tier 5 via the lifecycle, is the chunk **frozen** (can never demote further than tier N for some floor N), or can it freely cycle 0↔5 forever based on signals? The phrase "pure alloy" implies a sticky top state, but the pitch elsewhere insists "tracks signals and adjusts" — implying full mobility. v1 plan defaults to full mobility (no floor, no ceiling, monotonic neither way). Confirm.

### Q-010 · Hook nudge throttle — per-session or per-day?
**Raised:** 2026-05-20 (Architect, plan)
**Blocks:** install/hooks/melt-nudge.sh (Phase 6)
**Context:** Pitch: "Marker file prevents repeated nudging within a session." So per-session. But Claude Code's session boundary is `/clear`, not OS-session. If a user runs five `/clear` cycles in a workday, they'd get five nudges — possibly too many. v1 plan implements per-session (per pitch). Worth confirming whether a "max one per N hours" cap on top of the session marker would help.

### Q-011 · `.failed/` patch-marker on-disk schema
**Raised:** 2026-05-20 (Architect, post-Q-001 resolution)
**Blocks:** mp/lib/patch.sh failure-recording path (Phase 1), mp:learn `patch-triage` proposal payload (Phase 5)
**Context:** Q-001's resolution requires `patch.sh` to record each failed patch attempt to `~/.melt/<skill>/patches/.failed/`. The marker needs enough information for `mp:learn patch-triage` to compose a useful LLM proposal: the original patch hunk, the upstream excerpt the patch tried to match against, `git apply` rejection text, and a timestamp. Open: does each failure get one file with everything inline (e.g., `001-fix-typo.patch.failed` as a structured plain-text envelope with `--- patch ---` / `--- upstream excerpt ---` / `--- reject ---` / `--- timestamp ---` sections), or a directory per failure (`001-fix-typo/{patch,upstream,reject,meta.json}`)? File-per-failure is simpler to enumerate and matches the existing `001-…patch` naming style. v1 plan default: single file with delimited sections. Confirm or override before Phase 1 patch.sh implementation.

### Q-015 · `mp:learn refactor` near-duplicate detection algorithm
**Raised:** 2026-05-20 (Skills-B, post-Phase-5 implementation pass)
**Blocks:** nothing for v1 — `mp:learn refactor` ships with title-only matching; FTS5 NEAR-based detection deferred to a later iteration.
**Context:** The pitch describes `mp:learn refactor` as identifying "duplicate / overlapping chunks" and proposing consolidation. v1 implementation by Skills-B uses **title-only matching** (group chunks whose frontmatter `title:` matches by case-insensitive substring or by normalized-token overlap). A more accurate approach would use FTS5 `NEAR()` queries over chunk bodies (e.g., for each chunk, query the index for `body NEAR/10 <key-terms-from-this-chunk>` and propose any chunk whose body returns the candidate with a high score as a refactor target). Deferred because: (a) title-only catches the most common case (same-topic chunks accidentally created twice), (b) FTS5 NEAR semantics need tuning per-corpus and v1 has no calibration data, (c) the LLM that consumes refactor proposals can do its own deep comparison anyway. Open as a future enhancement, not a v1 blocker.

## Resolved

### Q-001 · Patch apply ordering & failure semantics — RESOLVED 2026-05-20
**Decision:** `mp/lib/patch.sh` attempts each patch in numeric order; on failure, **records a marker** in `~/.melt/<skill>/patches/.failed/` (one file per failed patch, e.g., `002-fix-broken.patch.failed`) containing the patch hunk, the upstream excerpt the patch tried to match, the `git apply --check` rejection output, and an ISO-8601 timestamp. Apply pipeline does **not** auto-skip or auto-stop based on a policy — it records the failure marker and **continues** attempting the rest of the patches against the current (partially-patched) content; markers accumulate for every subsequent failure. The apply pipeline itself is policy-free.

`mp:learn` gains a new subcommand (`mp:learn patch-triage`) which sweeps `~/.melt/*/patches/.failed/` markers and emits a per-marker proposal to the calling LLM: regenerate the patch, hand-rewrite it, delete it, or defer. Policy lives in `mp:learn`, not in the apply pipeline.

**Rationale (user verbatim):** "when patch is not working then we should note it inside skill directory (in our directory) and next time when we do learn we should find all this patches that don't apply and llm should figure out what to do with them on case by case basis"

**Landed in:** `plans/architecture.md` (mp/lib/patch.sh contract + new `.failed/` storage box + `mp:learn patch-triage` row); `plans/build_order.md` Phase 1 (patch.sh acceptance criteria), Phase 5 (`patch-triage` subcommand added).

**Spawned follow-ups:** Q-011 (the `.failed/` marker file schema).

### Q-003 · Hook install path & user settings location — RESOLVED 2026-05-20
**Decision:** Two-part. (1) **Hook scripts are harness-agnostic.** `melt-nudge.sh` and `melt-resume.sh` are pure POSIX sh; their bodies emit text on stdout in a shape that works regardless of which harness (Claude Code, Cursor, Codex, hand-run wrapper) is invoking them. No Claude-Code-specific JSON, no SessionStart-event field assumptions baked in. (2) **Installer does NOT mutate harness config.** Instead, `install/install.sh` (renamed from `install-claude-md.sh`) seeds `~/.melt/`, copies the hook scripts into place, and produces a harness-agnostic "register these hooks" instruction (manifest) — listing each script path + the hook-event slot it wants (e.g., `Stop`, `SessionStart:clear`) + a short description. The **calling agent** (the LLM running the installer) then translates the manifest into the actual harness's config write (`~/.claude/settings.json`, `.cursorrules`, etc.).

**Rationale (user verbatim):** "llm should write for us. we just say register this scripts in clean session hook. it should be llm agnostic."

**Landed in:** `plans/architecture.md` (renamed installer box + new manifest edge + hook scripts re-labelled "harness-agnostic"); `plans/build_order.md` Phase 6 (acceptance criteria rewritten — installer emits manifest, never touches settings.json).

**Spawned follow-ups:** Q-012 (manifest format — JSON vs. markdown vs. stdout TSV); Q-013 (does the task-intake rule install split out into a separate script?).

### Q-007 · Tier dir naming + co-existence with SKILL.md — RESOLVED 2026-05-20
**Decision:** **Rename tier dirs throughout the spec** from bare `0/`..`5/` to suffixed **`0-melting-pot/`..`5-melting-pot/`**. Rationale: avoids namespace collision with random `0/` or `1/` directories that may already exist in third-party repos and makes the convention's intent self-evident on inspection.

**Co-existence rule:** if a registered upstream repo contains `N-melting-pot/` directories, those are treated as canonical native-format tiers. `mp/lib/discover.sh` **symlinks** each upstream `N-melting-pot/` dir into `~/.melt/<skill>/N-melting-pot/` so the search/load pipeline reads everything from the overlay path uniformly without re-traversing into upstream on every call (cheaper + symmetric with overlay-born tiers).

**Partial-coverage rule:** if upstream has only some tiers (e.g., `0-melting-pot/`..`3-melting-pot/` but no `4-` / `5-`), the **overlay supplies everything for that skill** — do NOT mix-and-match partial upstream tiers with overlay tiers in the same skill. Once melting-pot detects upstream native-format tier dirs, melting-pot owns the entire tier stack for that skill (full-overlay mode).

**SKILL.md co-exists per the original rule:** `SKILL.md` indexed at tier 5 alongside any `5-melting-pot/*.md` files at the same tier.

**Rationale (user verbatim):** "let's call our dirs 0|1|2-melting-pot if their repo has it then use them (it means they should be 'our' structure) we should ln them to our dir so our search system will not break. and if it has 0,1,2,3, and not 4,5 then use our system entirely."

**Landed in:** `plans/architecture.md` (hub diagram label rename + storage section + discover.sh contract + new "partial-coverage / full-overlay mode" invariant); `plans/build_order.md` (cherry-pick map for `mp_discover_skills`, `mp/lib/tier.sh` acceptance criteria, every example path); references throughout open_questions.md.

### Q-008 · Backwards-compat with `~/.sc/repos.patterns` — RESOLVED 2026-05-20
**Decision:** **Clean fork.** melting-pot reads ONLY `~/.melt/repos.patterns`. No runtime fallback to `~/.sc/repos.patterns`. The installer offers an optional `--copy-from-sc` flag which performs a one-time `cp ~/.sc/repos.patterns ~/.melt/repos.patterns` if the destination doesn't exist — that's the migration helper, not a runtime path.

**Rationale (user verbatim):** "Clean fork to `~/.melt/repos.patterns`"

**Landed in:** `plans/architecture.md` (storage section — `~/.melt/repos.patterns` is the sole config path); `plans/build_order.md` Phase 6 (installer `--copy-from-sc` flag in acceptance criteria).

### Q-012 · Installer manifest contract — what does the harness-agnostic emit look like? — RESOLVED 2026-05-20
**Decision:** **Markdown only.** `install/install.sh` writes a single `install/REGISTER-HOOKS.md` file using structured tables — one row per hook with columns: `script-path` / `hook-event-slot` / `description` / `install-target-hint`. The calling LLM reads the markdown and registers each hook in whatever the current harness expects. No stdout TSV mode (`--emit-hook-manifest` dropped). No JSON variant. Single source of truth.

**Rationale (user verbatim):** "Markdown only"

**Landed in:** `plans/architecture.md` (MANIFEST mermaid node simplified to drop "+ --emit-hook-manifest TSV"; installer-component edge list pruned; file-layout box for `install/REGISTER-HOOKS.md` is now sole manifest artifact); `plans/build_order.md` Phase 6 acceptance criteria (drop `--emit-hook-manifest` flag from `install.sh` scope; manifest schema spec narrowed to "structured markdown tables"); cherry-pick map row for `install.sh --emit-hook-manifest` removed.

### Q-013 · Should the task-intake rule install split into its own script? — RESOLVED 2026-05-20
**Decision:** **Bundle — single `install/install.sh`.** One installer does both. (1) Seeds `~/.melt/`, copies hooks, emits `install/REGISTER-HOOKS.md` (per Q-012). (2) Emits `install/task-intake.md` as the rule block the calling LLM appends to whatever the current harness uses as its global rules file (`~/.claude/CLAUDE.md` in Claude Code, `.cursorrules` in Cursor, etc.). DevOps implements both halves in a single script — no `install-rules.sh` split.

**Rationale (user verbatim):** "Bundle — single `install/install.sh`"

**Landed in:** `plans/architecture.md` (installer responsibilities + AGENT edges already cover both manifest reads — no diagram change needed); `plans/build_order.md` Phase 6 acceptance criteria already names `install.sh` as the single artifact emitting both `REGISTER-HOOKS.md` and `task-intake.md` (matches v1 default — no change required beyond removing the "split" Q-ID).

### Q-014 · `mp_append_status_history` duplication bug — RESOLVED 2026-05-20
**Decision:** **Closed as fixed in code.** Surfaced by Skills-B during Phase 5 implementation while integrating `mp/learn/action {promote,demote}` with `mp/lib/tier.sh`'s `mp_append_status_history`. Backend-Lib confirms the duplication has been fixed in `mp/lib/tier.sh`; a regression test (`t_LIB_<n>_append_status_history_idempotent`) verifies that calling the helper twice for the same `(chunk, tier, reason, timestamp)` tuple does not add a duplicate row to the chunk's `status_history:` block. Recording here for audit trail; no further architectural impact.

**Rationale:** Defensive — when promote/demote ran in close succession (e.g., during `mp:learn eval` sweeps that touched the same chunk on a back-and-forth), the original awk-in-place edit appended a new history entry on every call even when an identical entry already existed. Fixed by reading the current `status_history:` block, checking for exact-line duplication before appending. Invariant now enforced by test.

**Landed in:** `mp/lib/tier.sh` (fix); `test/run-tests.sh` (regression test). Not architecturally load-bearing — no plan-file change required.

## Archive

(none yet)
