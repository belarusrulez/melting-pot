# melting-pot — e2e test-scenario menu (`claude -p` docker harness)

> Wave-2 deliverable for team `docker-e2e-tests`. The MENU of e2e scenarios that
> drive the five melting-pot skill CLIs through **real `claude -p` headless runs**
> in a docker harness. Every scenario is grounded in the two Wave-1 contracts:
> - `plans/e2e-headless-contract.md` — what's drivable/observable in `-p`, oracle gotchas.
> - `plans/e2e-groundtruth-contract.md` — per-CLI exit codes, mutated state, golden-corpus reuse.
>
> **Author:** QA / test-scenario designer. **Date:** 2026-06-04.

---

## Feasibility spike — does a NL prompt reliably fire the search tool? (PARTIAL — interrupted at design-phase close)

Ran the **exact menu prompts** for 5 scenario types via real `claude -p` (haiku, stream-json, NO retries) on the dev host. The run was **stopped early at design-phase close (~run 3 of a planned 5×)** — treat these as **directional, not statistically settled**; the critic correctly classes the full N=5 sweep as **build-phase validation** (needs the seeded container + golden corpus, not the dev host).

**Partial results (11 runs, $0.45 total; "fired_search" = a `Skill(search)` tool_use exists):**

| scenario (exact menu prompt) | fired search / runs | turns | note |
|---|---|---|---|
| D-agent-exact | 3 / 3 | 4–6 | clean every time |
| D-agent-synonym | **1 / 2** | 8 / **1** | **one non-fire**: agent answered from prior knowledge, `num_turns:1`, no tool_use — the exact failure mode the Critic flagged |
| D-agent-crossdomain | 2 / 2 | 8 | fired both |
| L-load-basic | 2 / 2 | 4–8 | fired search both; one run also ran `list/action` (extra exploration — tolerated) |
| F-loop-full | 2 / 2 | 15 | fired search both, BUT **never reached `load/action`/`learn promote`** — on the dev host the `git-rebase` native fixture isn't in `repos.patterns`, so the agent couldn't find the chunk and flailed with `find`/`ls`. **F-loop's load→use→promote chain is only testable with the seeded container fixture.** |

**Three takeaways for the build phase:**
1. **The Critic's concern is real and reproduced.** Intent/synonym prompts (no skill vocabulary) sometimes don't fire the tool at all (agent self-answers). **Mitigation already in the menu:** the CHOICE assertion is retry-eligible 2× (§0.6); additionally, **strengthen synonym/intent prompts with an explicit imperative** ("You MUST use the search skill before answering") — the headless contract's verified working prompt form. Recommend the build phase re-run N≥10 per prompt on the **seeded container** and flag any prompt with >20% non-fire as needing prompt-hardening.
2. **F-loop / L-load multi-step chains can't be validated on the dev host** — they need the golden `test/skills` corpus seeded (the live `repos.patterns` points elsewhere). The *search* step fires reliably; the *load+promote* steps are gated on the fixture. This is a fixture/image dependency, not a feasibility blocker.
3. **`Skill(search)` firing itself is solid** — 10/11 runs fired, `is_error:false` on all 11, cost in the predicted $0.02–0.10 band. The keystone assumption (NL prompt → agent chooses the search skill) holds.

---

## 0. Reading this menu — shared conventions (read once, applies to every scenario)

These are baked into EVERY scenario below; the per-scenario rows only call out deltas.

### 0.1 The two GATING gotchas (from headless contract §0)
- **G1 — no `/slash` skills in `-p`.** Every prompt is **natural language** ("Use the search skill to…", "Find a skill that…"). The oracle asserts the agent *chose* to fire the skill by parsing `stream-json` tool_use events. NEVER `claude -p "/search …"`.
- **G2 — exit code is `0` even on API failure.** The oracle parses `result.is_error` / `result.subtype` from JSON. `$?` is only trusted for crash / usage / budget / `timeout`(124) classes.

### 0.2 Standard invocation (CI form, headless contract §1)
```bash
timeout 300 claude -p "<prompt>" \
  --model claude-haiku-4-5-20251001 \
  --output-format stream-json --verbose \
  --allowedTools "Skill,Bash,Read,Write" \
  --permission-mode dontAsk \
  --max-budget-usd 0.25 \
  --no-session-persistence
```
- **Model pinned** to a full ID (determinism). Default **haiku** unless a scenario's MODEL column says otherwise.
- `--bare` is **OFF the table** for any scenario firing an mp skill — RESOLVED empirically (architecture §3a-bis, §6): `--bare` skips PERSONAL-skill discovery so the mp skills VANISH from `init.skills[]` and the agent can't choose them. Determinism comes instead from a **pristine `$CLAUDE_CONFIG_DIR` with NO `--bare`** (gives `mcp_servers:[]` + zero plugin/caveman bleed — the same determinism `--bare` was after, without the skill-blindness). Registration = two distinct symlink sets: `$CLAUDE_CONFIG_DIR/skills/<skill>` (lets the `Skill` tool *see* it) + `$MP_HOME/<skill>/action` (lets Bash *run* it).
- **`--json-schema`** is added for ranking-quality scenarios (D-family) to get a cheap `structured_output.top_skill` self-report — but the oracle ALWAYS cross-checks the raw `tool_result.content` too (structured output is a self-report, headless contract §0b-Q3).

### 0.3 Isolation (groundtruth contract §0, §5)
- Each scenario gets a **fresh sandbox `$MP_HOME`** and a per-scenario `$MP_PATTERNS`. State assertions read only inside that sandbox.
- **Registered layer** = `repos.patterns → <repo>/test/skills` (the ~79-skill golden corpus). Seed with `printf '<abs>/test/skills\t*\n' > $MP_HOME/repos.patterns`.
- **Overlay layer** starts empty; mutation scenarios mint their own overlay skill via `crud scaffold` (never touch the corpus).
- Build the index once per fresh sandbox: `sh $MP_HOME/search/action reindex`.

### 0.4 The oracle's two ground-truth surfaces (every scenario asserts on at least one)
1. **stream-json tool I/O** — the `tool_use`(Skill/Bash) + matching `tool_result.content`. This proves the agent *chose* + *fired* the CLI and *what it returned*. This is the canonical ground truth (G2 logic).
2. **`$MP_HOME` filesystem** — chunk file locations, `status_history` entries, `.failed` markers, `.trash/`, `.pending-transcript`, `.tool-count-<sess>`, `index.db` row fields. This proves state actually mutated.
- `result.is_error==false` and `result.permission_denials==[]` are asserted on EVERY scenario (omitted from rows below unless a scenario expects otherwise).

### 0.5 Skill identifier — resolve it per-run, don't hard-code (headless contract §0b-Q2, architecture §3a/§3b)
The `Skill` tool's `skill` field is the **bare dirname** (`"search"`/`"load"`/`"learn"`/`"list"`/`"crud"`) — confirmed even when the prompt says "mp-search", the agent emits `Skill(skill:"search")`. NEVER assert `"mp-search"`.
**Recommended oracle template upgrade (architect-blessed):** the oracle **preflight reads the `system/init` event's `skills[]` array and asserts the chose-clause against THAT**, rather than hard-coding the literal `"search"`. `init.skills[]` is the source of truth, so the oracle stays correct if a future install renames the registered skill. The `D2-name-crosscheck` scenario (prompt says "mp-search" → assert it fires dirname `search`) is still included to prove the prompt→dirname map is reliable, not just possible.

### 0.6 Flakiness doctrine (headless contract §6) — applied to every row
- **Assert on structure, never prose.** Tool fired (name + action path in `Bash.input.command`) = hard assert. `tool_result.content` CONTAINS expected slug = hard assert (substring/regex). Exact `result` wording = never assert.
- **Soft-assert** `num_turns` / `total_cost_usd` within a sane band (log, don't fail on small drift).
- **Retry policy:** a scenario that fails only its *agent-chose-the-tool* assertion (not its CLI-behavior assertion) may retry up to **2×** before hard-fail — model choice is the non-deterministic part. CLI-behavior assertions (exit code, state mutation) NEVER get retries; those are deterministic and a failure is real.
- **Per-scenario cost band** noted in the COST column (haiku ≈ $0.03–0.10/loop; smarter model higher).

### 0.7 What actually runs in Docker vs what is delegated (DEDUP — Critic-resolved 2026-06-04)
**The Docker harness runs ONLY the agent-loop scenarios** (D-agent-*, L, F, the agent-driven CRUD/learn ones, H, I) — "does a real agent CHOOSE and DRIVE the CLI correctly". That is the **~26 in-scope set** the Architect already landed in `e2e-architecture.md` §9, and it is what this menu's families enumerate.

**The `[direct]` scenarios in this file are NOT Docker scenarios** — they are a **prose checklist of the CLI-contract coverage the existing unit harness (`test/run-tests.sh`) already owns** (per architecture §1: don't duplicate the unit harness). Re-running them through a container wastes container overhead and adds flake surface for zero new signal. They are retained here only for **traceability** (so a reviewer can see which contract each agent scenario sits on top of), each tagged **[direct → unit harness]**. Do not build Docker plumbing for them.

**One exception that DOES add new value: the golden-corpus ranking metrics** (`D-rank-precision`, `D-rank-adversarial`). These aren't in `run-tests.sh` today. **Action: add them to `test/run-tests.sh` as a new `RANKING` family** (deterministic, no agent, ~free) — NOT to Docker. They score the ranker over all 55 qids; an agent in the loop adds nothing to a pure ranking-quality measurement. (The agent-in-the-loop *sample* of ranking — `D7`/`D-agent-*` — stays in Docker because there the value is "the agent chose to search at all".)

**Net:** Docker == agent-loop only (~26 scenarios, ~$2.50 worst-case). `[direct]` == unit-harness reminders. `D-rank-*` == new `RANKING` family in `run-tests.sh`.

---

## Priority legend
- **P0** — smoke: must pass on every commit; cheap, deterministic backbone + 2–3 cheap agent loops. Gates the build.
- **P1** — core coverage: the headline value (discovery quality, full loop, learn lifecycle). Run on PR / nightly.
- **P2** — breadth / edge / nice-to-have: negative cases, hooks, install seam, cross-cutting metrics. Nightly / on-demand.

---

## Family D — Discovery fires + picks the RIGHT skill (the headline)

Stresses: `mp-search`. Ground truth: `test/golden/queries.tsv` (**119 graded data rows across 55 qids** [verified: 129 file lines = 1 header + 9 `# category:` comments + 119 data rows; grade distribution 55×grade-2 / 46×grade-1 / 18×grade-0 — one grade-2 target per qid]) + `RUBRIC.md`. Reuse precision@1/@3, MRR, NDCG@5.

> **Two sub-modes.** `D-rank-*` run the action DIRECTLY across all 55 qids (no agent) to score the ranker — that's the relevance benchmark, cheap and deterministic. `D-agent-*` wrap a single qid in `claude -p` to prove the agent *chooses* to search and surfaces the right skill — that's the headless-choice test. Both reuse the same ground truth.

| id | name | prompt to `claude -p` | expected agent action | oracle — assert exactly | model / cost | flake handling |
|---|---|---|---|---|---|---|
| **D-rank-precision** **[direct → RANKING family in run-tests.sh]** | ranker precision@1/@3 over corpus | *(none — direct)* `sh $MP_HOME/search/action --format tsv a1 a2 a3` per qid | n/a | For each grade-2 qid: target_skill appears, rank#1 ideally; compute **precision@1, precision@3, MRR, NDCG@5** over all 55 qids (119 graded rows); assert aggregate ≥ a pinned baseline (recorded as a fixture so regressions show). | none / ~$0 | none (deterministic) |
| **D-rank-adversarial** **[direct → RANKING family in run-tests.sh]** | grade-0 must NOT rank #1 | *(direct, per qid w/ grade-0 rows, e.g. q007 git-rebase=0, q013 git-rebase=0)* | n/a | The #1 result is *some* annotated skill for that qid (grade 2/1/0). **HARD FAIL** if a grade-0 row is #1 (lexical-bias regression). **COVERAGE FAIL** if #1 is unannotated. | none / ~$0 | none |
| **D-agent-exact** P0 | agent searches on an exact-vocab task | "I need to binary-search my git history to find which commit introduced a regression. Use the search skill to find the right skill, then tell me its name." (q001 → `git-bisect`) | `Skill(search)` → `Bash(sh ~/.melt/search/action …)` | tool_use `Skill.input.skill=="search"`; following `Bash.input.command` contains `~/.melt/search/action`; matching `tool_result.content` contains `git-bisect`. | haiku / ~$0.04 | retry choice 2× |
| **D-agent-synonym** P1 | agent searches on jargon (no literal overlap) | "Figure out when this regression appeared — which change broke it. Find me the skill for this." (q007 → `git-bisect`, distractor `git-rebase` grade 0) | search fires | `tool_result.content` contains `git-bisect`; and in the agent's final answer the chosen skill is NOT `git-rebase`. `--json-schema {top_skill}` → assert `structured_output.top_skill ~ git-bisect` AND raw content agrees. | haiku / ~$0.05 | retry choice 2× |
| **D-agent-crossdomain** P1 | lexical trap: "rebase shards" ≠ git-rebase | "I need to rebase database shards to relieve a hot shard — find the skill." (q013 → `db-rebalance-shards`, `git-rebase` grade 0) | search fires | `tool_result.content` Convergence top hit is `db-rebalance-shards`; assert `git-rebase` is NOT the agent's chosen answer. This is the discriminative lexical-bias scenario. | **sonnet** / ~$0.10 (smarter model better resists lexical pull) | retry choice 2× |
| **D-agent-intent** P1 | intent-only phrasing (no skill vocab) | "My SQL query is slow and I want to understand why — find a skill." (q006 → `sql-explain`) | search fires | `tool_result.content` contains `sql-explain`. | haiku / ~$0.04 | retry choice 2× |
| **D-agent-3axis-quality** P2 | agent passes 3 distinct axes (not 1) | "Use the search skill — and follow its instruction to pass three different query phrasings — to find a skill for cleaning up feature-branch commits before a PR." (q002 → `git-rebase`) | search fires with 3 positional args | **right-result (rigorous, Critic-tightened):** the `tool_result.content` contains a `## Convergence` section. Convergence only forms when a skill matches **2+ of the 3 fused axes** — so its presence *proves the action actually computed 3 distinct query rankings and fused them* (a single-axis or duplicated-axis call produces no Convergence / a `WARN: <3 queries`). This is a property of the *action output*, far stronger than counting quoted strings in `Bash.input.command` (which a clever agent could spoof with 3 near-identical strings). Also assert `git-rebase` is the Convergence top hit. | haiku / ~$0.05 | retry choice 2× |
| **D-agent-convergence** P2 | agent prefers Convergence section | (any qid with a strong grade-2) | search fires | `tool_result.content` has a `## Convergence` section AND the grade-2 target is inside it (axes>=2). | haiku / ~$0.04 | retry choice 2× |

---

## Family L — Load + use the composed body

Stresses: `mp-load` (+ `mp-search` upstream). Native fixtures: `git-rebase` (SKILL.md + 0/3 tiers), `melting-pot-native-demo` (meta.md + 0/5, no SKILL.md).

| id | name | prompt to `claude -p` | expected agent action | oracle — assert | model / cost | flake |
|---|---|---|---|---|---|---|
| **L-load-basic** P0 | search → load the body | "Find the skill for interactive git rebase, then load its full content so you can follow it." | `Skill(search)` → `Bash(search …)` → `Bash(sh ~/.melt/load/action git-rebase)` | a `Bash` tool_use whose command contains `load/action` and `git-rebase`; the `tool_result.content` contains the compose header `origin=` + `tiers present:` and at least one tier-chunk title (e.g. autosquash / conflict-toolkit). | haiku / ~$0.06 | retry choice 2× |
| **L-load-native-nomanifest** P1 | load a meta.md-only native skill | "Load the full content of the melting-pot-native-demo skill." | `Bash(load melting-pot-native-demo)` | exit/`is_error` ok; `tool_result.content` contains the tier-5 `canonical-format` chunk AND tier-0 `scratch-note` (SKILL.md absent — manifest came from meta.md). | haiku / ~$0.04 | retry 2× |
| **L-load-use** P1 | load THEN apply the content to a task | "Load the git-rebase skill and use its autosquash recipe to tell me the exact commands to squash my last 3 WIP commits." | search→load→reason | `load/action` fired; right-result: the agent's final answer contains a **specific command sequence unique to the loaded autosquash chunk** — assert it matches `git commit --fixup=` AND `git rebase -i --autosquash` (and ideally `git config rebase.autosquash true`). These tokens are NOT generic git knowledge phrased loosely — the `--fixup`+`--autosquash` *pairing* with the exact chunk wording is the discriminator that proves the chunk body (not the model's prior) drove the answer. (Tightened per Critic: a unique command sequence, not loose substring overlap.) | **sonnet** / ~$0.10 | retry choice 2× |
| **L-load-tiers-flag** P2 | agent restricts tiers | "Load only the tier-5 canonical content of melting-pot-native-demo." | `Bash(load … --tiers 5)` | command contains `--tiers 5`; result contains `canonical-format` but NOT the tier-0 `scratch-note`. | haiku / ~$0.05 | retry 2× |
| **L-load-nopatch-direct** **[direct → unit harness]** | raw upstream view | *(direct)* `sh load/action <skill> --no-patches` on a patched overlay skill | n/a | output header `patches applied: 0`; body lacks the patch's added text. | none / ~$0 | none |

---

## Family F — Full loop (the integration headline)

prompt → search → read manifest → load → do work → **REPORT USE** → `learn promote/demote`. Asserts the promotion gradient ACTUALLY moved. Target the native fixtures (only ones with promotable overlay chunks).

> **Setup for F scenarios:** the corpus's native fixtures get Q-007-symlinked into the overlay on first discovery, so their tier chunks are promotable through the overlay. For a clean before/after, prefer minting an overlay skill via `crud scaffold` (F-loop-scaffolded) so the chunk is overlay-owned, not a symlink target.

| id | name | prompt to `claude -p` | expected agent action chain | oracle — assert the gradient MOVED | model / cost | flake |
|---|---|---|---|---|---|---|
| **F-loop-full** P1 | search→load→use→promote | "Find and load the right skill to clean up my feature-branch commits, follow it to give me the squash commands, and since the overlay autosquash chunk helped, report that use back to the learn system." | `Skill(search)`→`Bash(search)`→`Bash(load git-rebase)`→ reason → `Bash(sh ~/.melt/learn/action promote git-rebase/autosquash-recipe)` | (a) search+load fired (as L-load-basic); (b) a `Bash` command contains `learn/action promote` + the chunk; (c) **filesystem:** chunk file moved `0-melting-pot/ → 1-melting-pot/`; (d) its `status_history` gained an entry `tier:1 reason:"promoted from tier 0"` (count entries before/after = +1). | **sonnet** / ~$0.12 | retry choice 2×; FS assertions no retry |
| **F-loop-scaffolded** P1 | full loop on an overlay-born skill | (pre-seed: `crud scaffold loopdemo` → `0-melting-pot/first.md`) "Search for the loopdemo skill, load it, and if its first chunk was useful promote it." | search→load→`learn promote loopdemo/first` | chunk now at `1-melting-pot/first.md`; `status_history` +1 "promoted from tier 0"; tool_result of promote contains `promoted: tier 0 -> 1`. | haiku / ~$0.08 | retry choice 2× |
| **F-loop-demote** P2 | use→found-misleading→demote | (pre-seed chunk at tier 1) "Load loopdemo; its first chunk was misleading for my task — demote it." | search/load→`learn demote loopdemo/first` | chunk back at `0-melting-pot/`; `status_history` +1 "demoted from tier 1". | haiku / ~$0.07 | retry choice 2× |
| **F-loop-noreport-negative** P2 **[soft]** | the loop-NOT-closed control | "Find and load the git-rebase skill and give me the squash commands." *(no instruction to report use)* | search→load→answer, ideally no learn call | **STATE (hard):** the chunk tier is UNCHANGED (no promotion happened) — this part always holds and IS asserted, because the system has no auto-promote path (verified: tier movement is caller-driven only, groundtruth §2). **CHOICE (soft, Critic-flagged):** whether the agent *refrained* from calling `learn promote` is **soft/inconclusive** — a smarter or over-eager model might call it unprompted, which is NOT a failure of the system under test (the system still wouldn't have moved a tier without an explicit good-use signal). So: if no `learn/action` tool_use appears → control PASSES cleanly; if one does appear → log INCONCLUSIVE (not FAIL), since F-loop-full already provides the positive proof that the loop *can* close. The load-bearing assertion is the unchanged-tier STATE; the no-learn-call is advisory. | haiku / ~$0.06 | choice soft (inconclusive, never fail); STATE hard |

---

## Family C — CRUD lifecycle

Stresses: `mp-crud`. Most run **[direct → unit harness]** (deterministic contract checks); a few agent-driven prove the agent can scaffold/validate on request.

| id | name | invocation | oracle — assert | priority | model/cost |
|---|---|---|---|---|---|
| **C-collision** **[direct → unit harness]** | collision-check | `crud collision-check <existing>` then `<free>` | exit 1 + colliding path on stderr when basename exists; exit 0 when free. | P1 | none |
| **C-scaffold-native** **[direct → unit harness]** P0 | scaffold native | `crud scaffold demo-native` | exit 0, stdout "scaffolded native"; FS: `$MP_HOME/demo-native/meta.md` + `0-melting-pot/first.md`; chunk `status_history` has tier-0 "scaffolded". | P0 | none |
| **C-scaffold-legacy** **[direct → unit harness]** | scaffold legacy | `crud scaffold demo-legacy --legacy --target-dir D` | FS: `<D>/SKILL.md`; no tier dirs. | P1 | none |
| **C-scaffold-dryrun** **[direct → unit harness]** | dry-run mutates nothing | `crud scaffold demo --dry-run` | exit 0; NO files created (FS unchanged). | P1 | none |
| **C-validate-pass** **[direct → unit harness]** P0 | validate a good skill | `crud validate git-rebase` | exit 0, stdout `OK: <dir>` + `patches: total=/failed=/stale=`. | P0 | none |
| **C-validate-fail-manifest** **[direct → unit harness]** | validate missing manifest | scaffold then `rm meta.md`; `crud validate` | exit 1 (missing manifest). | P1 | none |
| **C-validate-fail-frontmatter** **[direct → unit harness]** | bad frontmatter | corrupt frontmatter; `crud validate` | exit 1 (bad frontmatter). | P1 | none |
| **C-validate-warn-bare-tier** **[direct → unit harness]** | bare `N/` dir warns | create `7/` or bare `3/`; validate | exit 0 but warn about bare/ignored dir (Q-007: only `N-melting-pot/`). | P2 | none |
| **C-trash-restore** **[direct → unit harness]** P1 | trash then restore round-trip | `crud trash demo` → `crud restore <entry>` | after trash: skill moved to `.trash/<ts>-demo/` + `.mp-trash-meta.json` with `orig_path`; after restore: back at orig, meta removed. | P1 | none |
| **C-restore-refuses** **[direct → unit harness]** | restore over existing | trash, re-create at orig, restore | exit 1 (refuses, no clobber). | P2 | none |
| **C-patch-add-list-validate** **[direct → unit harness]** P1 | patch CRUD + list vs validate divergence | `crud patch-add <skill> good.patch`; `patch-list`; `patch-validate` | patch copied to `patches/NNN-…` renumbered; **patch-list** says `not-yet-attempted` (marker-based) while **patch-validate** dry-runs and says `applies`/`failed` — assert the documented divergence. | P1 | none |
| **C-patch-remove** **[direct → unit harness]** | remove patch + marker | add a bad patch (creates marker via reindex), `patch-remove` | patch file + matching `.failed` marker both gone. | P2 | none |
| **C-import-preview** **[direct → unit harness]** | preview a root read-only | `crud import-preview <root>` | TSV `path⇥name⇥desc⇥tiers⇥issues`; FS unchanged. | P2 | none |
| **C-agent-scaffold** P2 | agent scaffolds on request | "Use the crud skill to scaffold a new native skill called `agent-made`." | `Skill(crud)` → `Bash(crud scaffold agent-made)` | tool fired; FS: `agent-made/meta.md` + `0-melting-pot/first.md` created. | P2 / haiku ~$0.05 |
| **C-agent-patch** P2 | agent creates a patch against upstream | "Create a patch against the git-rebase upstream skill that adds a note to its SKILL.md, using the crud patch-add flow." | search→crud patch-add | a `Bash` command contains `crud … patch-add`; FS: `git-rebase/patches/NNN-*.patch` exists; origin flips `reg→mix` in next `list`/`search` row. | P2 / sonnet ~$0.12 |

---

## Family LR — Learn lifecycle

Stresses: `mp-learn`. Mostly **[direct → unit harness]** for the deterministic contract; agent-driven where "agent decides to run learn" is the value.

| id | name | invocation | oracle — assert (observable before/after) | priority | model/cost |
|---|---|---|---|---|---|
| **LR-promote** **[direct → unit harness]** P0 | promote moves up a tier | scaffold → `learn promote demo/first` | chunk `0→1-melting-pot/`; `status_history` +1 `tier:1 "promoted from tier 0"`; stdout `promoted: tier 0 -> 1`. Source tier dir left empty (assert on chunk *location*, not dir absence). | P0 | none |
| **LR-demote** **[direct → unit harness]** P1 | demote moves down | promote to tier 1, then `learn demote demo/first` | chunk back at `0-melting-pot/`; history +1 "demoted from tier 1". | P1 | none |
| **LR-demote-tier0-removal** **[direct → unit harness]** P1 | demote at tier 0 = removal | `learn demote demo/first` (chunk at tier 0) | exit 0, stdout `removed: …`; chunk file GONE; `cascade` ran to stderr flagging dependents. | P1 | none |
| **LR-promote-at-tier5** **[direct → unit harness]** | promote refused at ceiling | promote a tier-5 chunk | exit 1 + WARN "already at tier 5"; chunk unchanged. | P2 | none |
| **LR-promote-clobber** **[direct → unit harness]** | no clobber at destination | put a chunk at both tier 0 and tier 1 same name; promote tier-0 | exit 1 (target exists, no overwrite). | P2 | none |
| **LR-cascade** **[direct → unit harness]** | cascade flags dependents | chunk B `depends_on` chunk A; `learn cascade A` | exit 0; stdout `FLAG <B> depends on <skill>/A …`; **no mutation** (flag-only, Q-002). | P2 | none |
| **LR-refactor** **[direct → unit harness]** | refactor proposes only | two chunks w/ identical normalized title; `learn refactor --yes` | exit 0; prints the overlap group (≥2 members); **nothing consolidated** even with `--yes` (v1 proposal-only). Exit 1 if no overlaps. | P2 | none |
| **LR-patch-triage-marker** **[direct → unit harness]** P1 | broken patch → marker → triage | drop a known-bad `patches/001-bad.patch`; `reindex` (writes marker, stack CONTINUES); `learn patch-triage` | (a) FS: `patches/.failed/001-bad.patch.failed` with 4 sections (patch/upstream/reject/timestamp); (b) `search --format tsv` col 11 / `list` col 7 = `patches_failed=1`; (c) `patch-triage` exit 0, emits a numbered proposal w/ Choices regenerate/hand-rewrite/delete/defer. Exit 1 when no markers. | P1 | none |
| **LR-harvest-transcript-handshake** **[direct → unit harness]** P1 | transcript-mode handshake | write `.pending-transcript` (or pass `--transcript fixture.jsonl`); `learn harvest` | exit 0; prints the `.jsonl` path + size; **read-then-unlink**: re-run finds `.pending-transcript` GONE (handshake fires once). | P1 | none |
| **LR-harvest-apply-create** **[direct → unit harness]** P1 | harvest creates a tier-0 chunk | `echo '{"proposals":[{"action":"create","skill":"demo","chunk_name":"c","title":"T","body":"B"}]}' \| learn harvest --apply` | exit 0; FS: new chunk at `demo/0-melting-pot/c.md` (born tier 0) with proper frontmatter. | P1 | none |
| **LR-harvest-quality-guard** **[direct → unit harness]** P1 | dup-title WARN, still creates | pre-seed a same-skill chunk titled "T"; harvest --apply a `create` titled "T" (RRF self-hit ≥0.12) | **stderr** has the `_harvest_dup_warn` WARN; chunk STILL created (advisory only, exit unaffected). Commit d8d8ab0 guard. | P1 | none |
| **LR-harvest-stdin-tty** **[direct → unit harness]** | live-mode needs piped stdin | `learn harvest` with a TTY stdin (no `--apply`, no transcript, no pipe) | exit 2 (stdin is a TTY). | P2 | none |
| **LR-harvest-empty-json** **[direct → unit harness]** | empty/invalid stdin | `echo '' \| learn harvest --apply` | exit 1 (empty/invalid JSON). | P2 | none |
| **LR-agent-harvest-roundtrip** P2 | agent reads transcript then re-invokes | (seed `.pending-transcript` → fixture `.jsonl`) "Run the learn harvest flow: it will point you at a transcript — read it and re-invoke harvest with the proposals JSON on stdin." | `Bash(learn harvest)` → `Read(fixture.jsonl)` → `Bash(echo {…} \| learn harvest --apply)` | both harvest calls in stream; a `Read` of the `.jsonl` between them; FS: chunk created from a real proposal. Hardest agent scenario (multi-step state handshake). | P2 / sonnet ~$0.15 |
| **LR-agent-triage** P2 | agent decides to triage a broken patch | (seed bad patch + marker) "There's a broken patch in the pot — use the learn skill to triage it and recommend what to do." | `Skill(learn)` → `Bash(learn patch-triage)` | tool fired; `tool_result.content` names the failing patch id + offers the resolution choices. | P2 / haiku ~$0.06 |

---

## Family N — Negative / edge (exit-code + degenerate-state contracts)

Stresses: every CLI's error paths. All **[direct → unit harness]** (deterministic) except N-agent-nomatch which checks how an agent *reacts* to a no-match.

> **Watch the gotcha (groundtruth §1):** a *missing* `repos.patterns` makes `search`/`list` return **1 (no hits)**, NOT 2 — auto-reindex builds a valid empty index. Only `list-roots`/`doctor` surface **2** for missing config.

| id | name | invocation | oracle — assert | priority |
|---|---|---|---|---|
| **N-search-nomatch** **[direct → unit harness]** P0 | nonsense query → exit 1 | `search "qwxzv" "qwxzv" "qwxzv"` | exit 1; text "no hits" / json `{"results":[]}`. | P0 |
| **N-search-missing-patterns** **[direct → unit harness]** P1 | missing patterns ≠ config error | rm `repos.patterns`; `search a b c` | exit **1** (not 2) — empty index, no hits. Documents the gotcha. | P1 |
| **N-listroots-missing-patterns** **[direct → unit harness]** P1 | list-roots surfaces config err | rm `repos.patterns`; `search list-roots` (and `doctor`) | exit **2** (config error). | P1 |
| **N-search-badflag** **[direct → unit harness]** | bad flag → exit 2 | `search --bogus a b c` | exit 2. | P2 |
| **N-search-index-error** **[direct → unit harness]** | sqlite missing/FTS5 fail → 3 | run with `sqlite3` off PATH (or corrupt `index.db`) | exit 3. | P2 |
| **N-load-nosuchskill** **[direct → unit harness]** P0 | load unknown skill → 1 | `load does-not-exist` | exit 1 (no such skill). | P0 |
| **N-load-noarg** **[direct → unit harness]** | load no arg → 2 | `load` | exit 2 (usage). | P2 |
| **N-load-brokenmanifest** **[direct → unit harness]** P1 | manifest with bad frontmatter | scaffold, corrupt manifest, `load` | composes best-effort or errors per contract; assert documented behavior (no crash/traceback; deterministic exit). | P1 |
| **N-load-failingpatch-wrinkle** **[direct → unit harness]** P1 | mix-origin + SKILL.md + bad patch | overlay w/ only `patches/` (bad) over a SKILL.md upstream; `load` | KNOWN WRINKLE: exits **1** yet still prints composed doc to stdout. Marker is written when compose runs via reindex. Drive marker assertion via `reindex`, not via load's exit. | P1 |
| **N-list-empty** **[direct → unit harness]** | empty pot → exit 1 | empty `$MP_HOME`, empty/absent patterns; `list` | exit 1 (empty). `list --count` ⇒ `0`. | P1 |
| **N-list-badflag** **[direct → unit harness]** | bad flag → 2 | `list --bogus` | exit 2. | P2 |
| **N-agent-nomatch** P2 | agent handles no-match gracefully | "Use the search skill to find a skill for <wholly-unsupported task, e.g. 'fold proteins on a quantum annealer'>." | `Skill(search)` fires, returns no hits | `tool_result.content` indicates no hits; agent's final answer says so / offers to add a repo or scaffold (per search SKILL "When you can't find anything") — does NOT hallucinate a skill. | P2 / haiku ~$0.05 |

---

## Family H — Hooks (live headless observability)

Stresses: `melt-nudge.sh` (Stop), `melt-resume.sh` (SessionStart:clear). **Coordinate w/ devops on feasibility** — hooks fire only when the harness wires them into config AND supplies the live session id / transcript path. `--bare` SKIPS hooks (headless contract §1), so hook scenarios must run WITHOUT `--bare`, with an explicit `--settings` registering the hook, or invoke the hook scripts directly.

| id | name | how exercised | oracle — assert | priority | notes |
|---|---|---|---|---|---|
| **H-nudge-direct** **[direct → unit harness]** P1 | nudge threshold + once-per-session | invoke `melt-nudge.sh <sess>` N times (N≥`MP_NUDGE_THRESHOLD`, default 20; set low e.g. 3 for cheap) | `.tool-count-<sess>` increments each call; at threshold prints the "run mp-learn before /clear" nudge AND touches `.session-nudged-<sess>`; subsequent calls do NOT re-nudge (guard file present). | P1 | counter + guard files are the assertion surface; no model |
| **H-resume-direct** **[direct → unit harness]** P1 | resume writes pending-transcript | `melt-resume.sh <transcript.jsonl> <uuid>` | atomically writes `learn/.pending-transcript` containing `<transcript path>`; prints resume/harvest prompt. With NO transcript arg: fallback prompt, writes nothing. | P1 | tmp-then-rename atomicity |
| **H-resume-harvest-roundtrip** **[direct → unit harness]** P1 | resume → harvest consumes | `melt-resume.sh <path>` → `learn harvest` (no flag) | `.pending-transcript` written then GONE after harvest (read-then-unlink). End-to-end handshake. | P1 | links H + LR families |
| **H-nudge-live-session** P2 | nudge fires in a real `claude -p` turn | run a multi-tool `claude -p` (no `--bare`) with `Stop=melt-nudge.sh` wired via `--settings`, threshold set to fire within the turn's tool count | after the run, `.tool-count-<sess>` reflects the turn's tool calls; if threshold crossed, nudge text appears in the hook's captured stdout + `.session-nudged-<sess>` exists. | P2 / haiku ~$0.06 | **DEVOPS DEPENDENCY**: confirm hooks observable in headless mode + how stdout is captured. Highest feasibility risk in the menu. |
| **H-resume-live-clear** P2 | SessionStart:clear fires resume | drive a session, then trigger `:clear` with a real transcript path injected | `.pending-transcript` written with the live transcript path. | P2 | **DEVOPS DEPENDENCY**: how to trigger `:clear` + inject transcript headlessly. |

---

## Family I — Install / registration seam

Stresses: `install/install.sh` + the manual registration steps that make skills discoverable. Mostly **[direct → unit harness]**; these gate the IMAGE itself.

| id | name | invocation | oracle — assert | priority |
|---|---|---|---|---|
| **I-install-fresh** **[direct → unit harness]** P0 | installer seeds overlay | `install.sh` into a fresh `$MP_HOME` | exit 0; FS: `$MP_HOME/{learn,hooks,search,trash}/` exist; each `mp/*/SKILL.md` → `$MP_HOME/<skill>/action` link (or Windows shim); `REGISTER-HOOKS.md` + `task-intake.md` copied. | P0 |
| **I-install-patterns-stub** **[direct → unit harness]** P1 | writes patterns only if missing | install with NO patterns, then again WITH a custom patterns | first run writes a stub; second run does NOT overwrite the user's patterns. | P1 |
| **I-install-q003-invariant** **[direct → unit harness]** P0 | never mutates harness config | SHA-256 `~/.claude/settings.json` before/after install | hashes identical; installer exit 0 (Q-003). A breach is exit 4. | P0 |
| **I-install-dryrun** **[direct → unit harness]** | dry-run creates nothing | `install.sh --dry-run` | exit 0; FS unchanged. | P2 |
| **I-install-emit-manifest** **[direct → unit harness]** | manifest-only mode | `install.sh --emit-manifest-only` | prints the registration manifest; no FS writes. | P2 |
| **I-register-then-discover** **[direct → unit harness]** P0 | registration makes skills findable | full image bring-up: install → seed `repos.patterns → test/skills` → register skills with harness → `search reindex` → `list --count` | `list --count` ⇒ ~79; a smoke `search` returns hits (exit 0). This is the image-readiness gate every agent-loop scenario depends on. | P0 |
| **I-skill-tool-sees-skills** P0 | the `Skill` tool resolves mp skills | trivial `claude -p "Use the search skill to find a skill for git rebase."` post-registration | `system/init.skills[]` lists `search`/`load`/`learn`/`list`/`crud`; a `Skill(search)` tool_use actually fires. Regression-locks the resolved registration seam (pristine `$CLAUDE_CONFIG_DIR`, NO `--bare`, architecture §3a-bis/§6) — catches a future regression where skills vanish from discovery. | P0 / haiku ~$0.04 |

---

## Cross-cutting strategy

### Determinism / flakiness oracle strategy (consolidated)
1. **Two-tier assertions** per agent scenario: a **CHOICE** assertion (did the agent pick + fire the tool — retry-eligible 2×) and a **BEHAVIOR** assertion (exit code / `tool_result.content` substring / FS state — never retried). A scenario passes only if BOTH hold; flake is confined to CHOICE.
2. **Structure over prose** everywhere (headless §6) — substring/regex on `tool_result.content`, never equality on `result`.
3. **`--json-schema`** for D/L ranking scenarios → `structured_output.top_skill` is the **convenience PRIMARY signal, never the SOLE one**. HARD RULE: it's the model's self-report, not raw action output — a hallucinating model could fill it with a slug the action never returned, so the oracle MUST also assert the raw `tool_result.content` contains that slug. Structured field = convenience; observed tool I/O = ground truth (architect-confirmed, headless §0b-Q3, architecture §3b).
4. **Pin model + version**, omit `--fallback-model` in determinism scenarios; assert `system/init.model` matches expected.
5. **`[direct → unit harness]` variants do NOT run in Docker** (§0.7) — they're the deterministic regression coverage `test/run-tests.sh` already owns. The `D-rank-*` ranking metrics move to a new `RANKING` family in `run-tests.sh`. Docker runs agent-loop scenarios only.
6. **`timeout 300`** wraps every call → a hang is exit 124 (the only exit-code we trust for agent runs).

### Cost map (DOCKER agent-loop scenarios only — ~26, ≈$2.50 worst-case)
- **`[direct → unit harness]`** scenarios: NOT in Docker (run free in `test/run-tests.sh`). Excluded from this cost map.
- **Cheap agent (haiku):** D-agent-exact/synonym/intent/3axis/convergence, L-load-basic/native/tiers, F-loop-scaffolded/demote/noreport, C-agent-scaffold, LR-agent-triage, N-agent-nomatch, I-skill-tool-sees-skills — ≈ $0.04–0.08 each.
- **Needs a smarter model (sonnet):** D-agent-crossdomain (lexical-trap resistance), L-load-use (consume body), F-loop-full (multi-step chain), C-agent-patch, LR-agent-harvest-roundtrip (multi-step state handshake) — ≈ $0.10–0.15 each.
- **Worst-case run cost:** ~26 agent scenarios, most haiku + ~5 sonnet, with up-to-2× choice retries ≈ **$2.50** (down from the ~$6.90 the 69-row count would have implied). Per-scenario breaker `--max-budget-usd 0.30` (architecture §8); run-level ceiling `$MELT_RUN_BUDGET_USD`. **Billing note (headless §5):** after 2026-06-15 `claude -p` on subscription draws Agent-SDK credit → use a dedicated PAYG `ANTHROPIC_API_KEY` to isolate test spend.

### Which model for which scenario — heuristic
Use **haiku** when there's essentially one correct tool path and the assertion is "did it fire + return slug X". Use **sonnet** when the scenario tests *judgment* under ambiguity (lexical traps, multi-step chains, consuming a body, state handshakes) — haiku flakes more on those and the CHOICE retries get expensive.

---

## P0 smoke set (gates the build)

The minimal set proving the harness + image + core contracts are alive — split by which layer runs it (§0.7).

**Image-build / unit-harness gates (run in CI per-PR, free or near-free — NOT Docker agent runs):**
- **I-install-fresh**, **I-install-q003-invariant**, **I-register-then-discover** — image built + skills discoverable + config untouched. (`[direct → unit harness]` / image bring-up.)
- **C-scaffold-native**, **C-validate-pass**, **LR-promote**, **N-search-nomatch**, **N-load-nosuchskill** — core CLI contracts (`[direct → unit harness]`, owned by `test/run-tests.sh`).
- **D-rank-precision**, **D-rank-adversarial** — ranker quality + no grade-0-at-#1 regression (the new `RANKING` family in `test/run-tests.sh`).

**Docker agent-loop smoke (the genuinely-new coverage; haiku, ≈$0.04 each, dispatch/nightly per architecture §8):**
- **I-skill-tool-sees-skills** — the `Skill` tool actually resolves mp skills headlessly (the keystone — every other agent scenario depends on it). *(Spike-confirmed firing, see §Feasibility.)*
- **D-agent-exact** — agent CHOOSES to search and surfaces the right skill.
- **L-load-basic** — agent chains search→load and gets a real composed body.

Covers: image build, registration, discovery choice, ranking quality, load chain, learn gradient, two error paths. The 3 Docker agent loops cost ≈**$0.12**; the rest are free/near-free in the unit harness.

---

## Family / count / priority summary (DOCKER agent-loop scenarios)

This counts the **in-scope Docker set** only (matches architecture §9). The `[direct → unit harness]` rows that appear inside each family's table are NOT counted here — they're delegated to `test/run-tests.sh` (§0.7). For the full brainstorm including those delegated rows, see the per-family tables above.

| Family | Docker agent-loop scenarios | delegated to unit harness (`[direct]`) |
|---|---|---|
| D — Discovery | 6 (D-agent-*) | 2 (D-rank-* → new `RANKING` family) |
| L — Load | 4 | 1 |
| F — Full loop | 4 | 0 |
| C — CRUD | 2 (C-agent-*) | 12 |
| LR — Learn | 2 (LR-agent-*) | 12 |
| N — Negative | 1 (N-agent-nomatch) | 11 |
| H — Hooks | 2 live (H-*-live) + 3 direct-hook* | 3 direct-hook* |
| I — Install | 1 agent (I-skill-tool-sees-skills) | 6 (image bring-up) |
| **Docker total** | **~26 agent-loop** | **~46 in `run-tests.sh`** |

(*Hook direct-invocation variants run the `.sh` directly — cheap, no model — and are the proven fallback if live-session wiring (H3/H4) proves infeasible; counted with the unit-harness layer since they need no `claude -p`.)

## Open items for the team
- **[DEVOPS]** H-family live-hook scenarios (H-nudge-live-session, H-resume-live-clear): confirm hooks are observable + how stdout is captured in headless `claude -p`, and how to trigger `SessionStart:clear` + inject a live transcript. Highest feasibility risk; direct-hook variants (H-*-direct) are the fallback if live wiring proves infeasible.
- **[RESOLVED — architecture §3a-bis/§6]** `--bare` decision: `--bare` makes mp skills VANISH from `init.skills[]` (skips personal-skill discovery), so agent scenarios run WITHOUT `--bare` + a pristine `$CLAUDE_CONFIG_DIR` (zero plugin/caveman bleed, same determinism). Registration = two symlink sets (`$CLAUDE_CONFIG_DIR/skills/<skill>` to *see*, `$MP_HOME/<skill>/action` to *run*). `I-skill-tool-sees-skills` is retained as a standing image-readiness regression gate, not an open probe.
- **[ARCHITECT]** baseline metric values for D-rank-precision/adversarial: pin current precision@1/@3, MRR, NDCG@5 as a recorded fixture so regressions are detectable. Needs one clean run of the ranker over all 55 qids (119 graded rows). Python scorer is already in the image (architecture §8 decision #5).
