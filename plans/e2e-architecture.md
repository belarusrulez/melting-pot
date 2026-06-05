# melting-pot Docker E2E Harness — Integrated Architecture

> **Status: INTEGRATED + Critic-reviewed.** Single source of truth that the
> Report writes up. Composes both Wave-1 contracts + both Wave-2 deliverables +
> the Critic's verdict with architect rulings (§11). Two spikes run in parallel
> as validation, neither gating this design: QA agent fire-rate, DevOps live-hooks.
>
> Inputs (all delivered):
> - `plans/e2e-headless-contract.md` — CLI/headless expert (GREEN feasibility).
> - `plans/e2e-groundtruth-contract.md` — domain expert (per-CLI truth + 5 gotchas).
> - `plans/e2e-docker-design.md` — DevOps (container + lifecycle; `--bare` spike).
> - `plans/e2e-scenarios.md` — QA (scenario menu; see §9 + §11 for the post-dedup target).
>
> This whole effort is a **design deliverable — no working code yet.**

---

## 1. What this harness is for (and what it is NOT)

The existing `test/run-tests.sh` already covers the `mp/lib/*` layer + CLI
behavior with a sandboxed `$MP_HOME` and the golden corpus. It does **not** run
a real agent. The gap this harness fills is the **real-agent loop**: a natural-
language prompt → `claude -p` chooses to fire an mp skill → runs the `action`
script → reads the result → does work → reports use → `mp-learn` moves a chunk.

**In scope (only the agent-loop integration seams):**
- Skill *discovery actually firing* (agent chooses `Skill` → `Bash(action)`).
- *Right skill picked* — graded against `test/golden`.
- *Promotion gradient actually moves* after a reported good use.
- Hooks (`melt-nudge` / `melt-resume`) firing in a live session with a real transcript.
- Harness registration of skills + hooks (the README/INSTALL manual steps).

**Explicitly OUT of scope (already covered by the unit harness — do NOT duplicate):**
- `mp/lib/*` unit behavior, exit-code matrices for pure-CLI calls, tier math,
  in-memory patch apply mechanics. The e2e harness *invokes* the CLIs only as
  the agent would, and asserts on the agent's choices + resulting state — it is
  not a second CLI unit-test suite.

---

## 2. The two hard constraints that shape every scenario (from Wave 1)

1. **No `/slash` skills in `-p` mode.** Prompts MUST be natural-language
   ("Use the mp-search skill to find …; you MUST invoke the search skill") and
   the oracle asserts the agent *chose* to fire it. The choice is part of the test.
2. **Exit code is 0 even on API failure.** The oracle MUST parse
   `result.is_error` from JSON. `$?` is reserved for crash / usage / budget /
   timeout(124). Never gate pass/fail on `$?` alone.

---

## 3. Resolved cross-contract decisions

### 3a. Naming seam — RESOLVED (empirically): oracles assert the **dirname**
The README registers skills by hyphenated frontmatter `name:` (→ Claude Code
`/mp-search`), but `/slash` doesn't fire in `-p`, invocation is **path-based**
(`sh mp/search/action`), and — **confirmed by real `-p` runs** (headless contract
§0b) — the `system/init` event's `skills[]`/`slash_commands[]` arrays list the
bare dirnames (`search`/`load`/`learn`/`list`) with **NO `mp-` entry**. Even when
prompted "invoke the skill named **mp-search**", the agent emits
`Skill(skill:"search")`. The hyphenated `mp-` name does not survive into `-p`.
→ **Oracles assert `tool_use.input.skill == "search"` (and `load`/`learn`/`list`) — the dirname, never `"mp-search"`.**
→ **Robustness (QA template):** an oracle preflight MAY read the `init.skills[]`
   array and adapt to it — that array is the source of truth if a future install
   changes the registered name, so the oracle stays correct without hard-coding.
→ One QA cross-check scenario still warranted: prompt says "use the mp-search
   skill" → assert the agent fires dirname `search` (proves the prompt→dirname map
   is reliable, not just possible).

### 3a-bis. Registration mechanism — TWO distinct symlink sets (docker §0, verified)
The container makes the agent both *see* and *run* a skill via two separate links — **don't conflate them; both required for the full loop:**
1. **`$CLAUDE_CONFIG_DIR/skills/<skill>` → `<repo>/mp/<skill>/`** — makes the **`Skill` tool** see the skill (registration; gates whether the agent can *choose* it). This is INSTALL.md step 4 done Claude-Code-native, and is the spike's answer — without it, mp skills never appear in `init.skills[]`.
2. **`$MP_HOME/<skill>/action` → `<repo>/mp/<skill>/action`** — makes `sh $MP_HOME/<skill>/action` resolve when the agent runs **Bash** (this is `install.sh`'s job, already in the installer).
Confirmed empirically (DevOps spike, claude v2.1.162, dev host): with the clean config + symlinks and NO `--bare`, `init.skills[]` = `['crud','learn','list','load','search', …~12 binary builtins]` — all five mp dirnames present (no `mp-` entry), `slash_commands[]` lists the same five. Adding `--bare` → all five mp dirnames VANISH (only builtins remain). `--bare` skips PERSONAL-skill discovery so set (1) disappears → **`--bare` is off the table** for any scenario firing an mp skill. A pristine `$CLAUDE_CONFIG_DIR` (no `--bare`) gives the same determinism (`mcp_servers:[]`, zero plugin/caveman bleed) without the skill-blindness. The `init` event is emitted **pre-auth**, so this is verifiable with no `ANTHROPIC_API_KEY` / no billed turn.
> **One outstanding upgrade (fast-follow, NOT a Report gate):** all spikes ran on the **macOS dev host**; the shipping image is `debian:bookworm-slim` (glibc/dash/GNU coreutils). CLI expert to re-run the `init.skills[]` probe *inside the built Linux container* (DevOps hands off the image) to upgrade this from "verified on dev host" → "verified in the shipping image." The probe is pre-auth/free. Until then, treat Linux==macOS skill-visibility as a well-founded assumption, not yet container-confirmed.

### 3b. Universal oracle template (every scenario fills this in)
Parse `--output-format stream-json --verbose` (NDJSON). A scenario PASSES iff:
- **chose:** a `tool_use` event with `name=="Skill"` and `input.skill==<expected dirname>` exists;
- **fired:** a following `tool_use` `name=="Bash"` whose `input.command` contains the action path (e.g. `~/.melt/search/action`);
- **right result:** the matching `tool_result.content` contains the expected substring (slug / `axes=N` / chunk path);
- **clean:** final `result.is_error==false` AND `result.permission_denials==[]`;
- **state (for mutation scenarios):** assert the expected `$MP_HOME` filesystem change (see §4).
- **TOLERATE:** exact prose, `num_turns`/cost drift (soft-log only). Assert on STRUCTURE/substrings, never free text.

> **ANTI-SILENT-NO-OP INVARIANT (load-bearing — the harness's central safety property).** The single most dangerous failure mode is an agent that **answers from its own knowledge and never fires the mp skill** — the scenario would "pass" by free-text inspection while testing nothing. The "chose" + "fired" conditions above make this a **HARD FAIL by construction**: an agent-loop scenario with **zero matching `Skill`/`Bash` tool_use events is a FAILURE, never a pass** — there is no free-text fallback path to green. Concretely the oracle asserts `count(tool_use where name=="Skill" && input.skill==<dirname>) >= 1` AND the paired `Bash(action)` fired; absent either → FAIL (and it's a BEHAVIOR-class failure, NOT retry-eligible — a no-fire is a real signal, not flake; only the *agent-chose* portion of a partial run is retried per §0.6). This is why every agent prompt is imperative ("you MUST invoke the X skill") and why **BLOCKER 1's feasibility spike** (§11) measures the fire-rate empirically before any agent scenario is trusted.

**`--json-schema` (recommended default for ranking-quality scenarios) — VERIFIED co-exists.** Forcing a schema does NOT suppress/alter the tool-call path: the `Skill`+`Bash` `tool_use` events are preserved AND the `result` object gains a `structured_output` field (e.g. `{"fired_search":true,"top_skill":"s:commit"}`). Use it as the *convenient primary* assertion for cheap deterministic scenarios — **but `structured_output` is the model's self-report, not raw action output** (a hallucinating model could fill it with a slug the action never returned). So ALWAYS also assert the raw `tool_result.content` contains that slug. Observed tool I/O is ground truth (same logic as the `is_error` rule).

### 3c. Auth / cost / determinism (from headless contract)
- Auth = `ANTHROPIC_API_KEY` env (macOS keychain not portable). Dedicated PAYG key for CI (subscription→Agent-SDK-credit split lands 2026-06-15; isolate test spend).
- ~$0.03–0.10 / scenario on haiku; `--max-budget-usd 0.25` per-scenario breaker; wrap in shell `timeout` (no `--timeout`/`--max-turns` flags exist).
- Pin full model ID (`claude-haiku-4-5-20251001`); neutralize local config (`--bare` or clean `$CLAUDE_CONFIG_DIR` — caveman plugin bleed proved config bleed is real); no `--fallback-model` in determinism scenarios; consider `--json-schema` for trivial "did it pick skill X" oracles.

---

## 4. The five oracle-biting gotchas (baked into assertions — from domain contract)

These will silently produce false passes/fails if an oracle author isn't warned:

1. **Missing `repos.patterns` ⇒ search/list exit `1` (no hits), NOT `2`.** Auto-reindex builds a valid empty index. Only `list-roots`/`doctor` return `2` for missing config.
2. **promote/demote use `mv` and leave the empty source tier dir behind.** Assert on chunk file *location* + appended `status_history` entry, NEVER on dir absence. Demote at tier 0 = `rm -f` (chunk gone) after cascade-flagging dependents.
3. **`mp-load` on a mix-origin skill (overlay = patches-only) with a failing patch exits `1` while still printing the composed doc.** The `.failed` marker is written when compose runs — drive marker creation via reindex / clean overlay, not via `mp-load` exit status.
4. **`patch-list` (marker-based) vs `patch-validate` (real dry-run apply) DISAGREE before any marker exists:** list=`not-yet-attempted`, validate=`failed`. Both read-only.
5. **Hooks need the harness to inject the live transcript path / session id** (arg or env) or `melt-resume.sh` writes nothing. Container must feed a real `.jsonl` path to exercise the harvest read-then-unlink handshake.

---

## 5. Fixture seeding (from domain contract §5) — what every scenario starts from

1. `repos.patterns` → `<repo>/test/skills` (registered layer; 79 skills [verified]).
2. Clean sandbox `$MP_HOME` per scenario (overlay starts empty) for state isolation.
3. Mutation scenarios: `crud scaffold <name>` → overlay-born native skill w/ a tier-0 chunk to promote/demote without touching the corpus.
4. Patch scenarios: drop a known-bad + known-good `patches/NNN-*.patch` under an overlay skill → exercise `.failed` marker + triage.
5. Hook scenarios: a fixture `.jsonl` transcript path fed to `melt-resume.sh`.
6. Ranking scenarios: reuse `test/golden/queries.tsv` (128 graded rows; grades 2/1/0/implicit-1) → P@1 / P@3 / MRR / NDCG@5 + adversarial guard (grade-0 at #1 = hard fail). Native fixtures `git-rebase` + `melting-pot-native-demo` are the promotion-loop targets.

---

## 6. Open items carried into Wave 2

- **[DevOps #1 spike — RESOLVED 2026-06-04, empirically: NO `--bare`]** Verified against `claude` v2.1.162 on the dev host via the `system/init` event (emitted **pre-auth**, so it probes even on a keychain-only host with no API key):
  - **No `--bare`** + clean `CLAUDE_CONFIG_DIR` with each `mp/<skill>/` symlinked into `<dir>/skills/<skill>` → all 5 mp skills (`search`/`list`/`crud`/`load`/`learn`) appear in `init.skills[]` **and** `init.slash_commands[]`. Agent can fire them.
  - **`--bare`** + the same config dir → all 5 mp skills **VANISH** (only binary-builtin skills remain). `--bare` skips *personal*-skill discovery; the `--help` line "Skills still resolve via /skill-name" refers to **builtin** skills only.
  - Determinism without `--bare`: a pristine `CLAUDE_CONFIG_DIR` already gives `mcp_servers:[]` and **zero plugin/caveman bleed** (verified) — same determinism the `--bare` recommendation was after, without the skill-blindness. So `--bare` is **off the table** for any scenario firing an mp skill.
  - **Registration mechanism:** `ln -s <repo>/mp/<skill>/ $CLAUDE_CONFIG_DIR/skills/<skill>` per skill (INSTALL.md step 4, done Claude-Code-native). Details + the two-distinct-symlink-sets caveat in §8.4. CLI expert's §6 read ("likely NO under `--bare`") confirmed.
- **[CLI expert follow-ups] — ALL RESOLVED** (headless §0b): (a) clean-config preferred over `--bare` in Linux; (b) identifier = bare dirname `search` (NOT `mp-search`), confirmed even when prompted with the hyphenated name; (c) `--json-schema` co-exists cleanly, tool_use events preserved, `structured_output` populated — but it's a self-report, cross-check raw `tool_result`. See §3a, §3b.
- **[QA]** Whether to split ranking-quality scenarios (deterministic, cheap, possibly `--json-schema`) from full-loop scenarios (multi-turn, costlier) into two tiers so CI can run the cheap tier per-commit and the loop tier nightly.

## 7. Wave-2 deliverables

- **§8 Dockerfile + harness lifecycle** (DevOps) — **DELIVERED**, full design in `plans/e2e-docker-design.md`. Summary below.
- **§9 Scenario menu** (QA) — **DELIVERED** (§9 below): each scenario = id + intent + NL prompt + expected `skill` dirname + oracle assertions (filled §3b template) + which CLI/hook it stresses + fixture deps + flakiness handling + cost tier.

## 8. Container + harness lifecycle (DevOps — integrated summary)

Full design: `plans/e2e-docker-design.md`. Load-bearing decisions:
- **Base:** `debian:bookworm-slim` (glibc — native `claude` build needs it; alpine/musl risky), digest-pinned. Deps: `git`, `jq`, `python3` (NDCG/MRR scoring), `sqlite3` 3.40 (FTS5 — build-time assert `CREATE VIRTUAL TABLE … fts5`), coreutils. **Pin + build-time-assert CLI `2.1.162`** (a CLI bump can change the `stream-json` shapes both contracts depend on). Non-root `melt` user, writable `$HOME`.
- **Invocation (final — NO `--bare`):** `timeout 300 claude -p "$PROMPT" --model claude-haiku-4-5-20251001 --output-format stream-json --verbose --allowedTools "Skill,Bash,Read,Write" --permission-mode dontAsk --max-budget-usd 0.25 --no-session-persistence < /dev/null` (redirect stdin or the CLI waits 3s). `[--json-schema …]` for ranking scenarios.
- **Seeding = two overlays per scenario:** (A) `$CLAUDE_CONFIG_DIR/skills/<skill>` symlinks + minimal `settings.json` (permissions, hooks only if needed) — registration (§3a-bis #1); (B) `$MP_HOME` via real `install.sh` + `repos.patterns → test/skills` + `reindex` + smoke `list --count`==79 — runtime (§3a-bis #2).
- **Isolation:** **per-RUN container, per-scenario `mktemp -d`** for `$CLAUDE_CONFIG_DIR`/`$MP_HOME`/`$MP_PATTERNS` — full state isolation without paying N container starts. (Full per-scenario container reserved for any scenario mutating outside `$RUN`; none identified.)
- **Auth/cost:** `ANTHROPIC_API_KEY` injected only, never baked; dedicated PAYG key (billing isolation post-2026-06-15). Layered breaker: `--max-budget-usd 0.25`/scenario (canonical, matches §3c + headless §5) + run-level `$MELT_RUN_BUDGET_USD` ceiling (~$3 post-dedup) summing `total_cost_usd`.
- **Collect:** persist `run.ndjson` + `$MP_HOME` tree + `index.db` + stderr/exit out of the container (the assertion surface; survives teardown).
- **CI:** GitHub Actions `workflow_dispatch`/nightly — **NOT per-PR** (cost + API dep). Free `test/run-tests.sh` stays per-PR. GHA layer cache on the heavy CLI+apt layer; tag carries CLI version. **Failure taxonomy:** API-unreachable/429/5xx/timeout(124) → **SKIP** (1 light retry first); model-404/auth/budget-exceeded/assertion-mismatch → **FAIL**. Always upload artifacts (`if: always()`).

### Architect decisions on DevOps's 6 open items (docker §6)
1. **CLI installer pin** — accept: pin + build-time-assert `2.1.162`; confirm exact native-installer invocation at build. The assert is the contract.
2. **Hooks** — OFF by default, ON only for hook-handshake scenarios. **Confirmed scope.**
3. **task-intake.md** — injected (via `--add-dir` CLAUDE.md) only for intake-loop scenarios; omitted elsewhere (it changes agent behavior). **Confirmed.**
4. **`--network none` for assertion steps** — **DEFER.** Don't split execs now; it's a hardening pass, out of scope for the design deliverable. Revisit if allowlists prove brittle (then `--network none` + `--dangerously-skip-permissions` is the sanctioned fallback per headless §2).
5. **jq + python3 both** — **accept image weight.** Python owns golden-corpus NDCG/MRR/P@k scoring; jq owns tool-fired/state substring asserts.
6. **Builtin-skill noise** — already handled in §3b: assert specific slugs, never "exactly N skills exist". The ~12 binary builtins (deep-research, code-review, …) are inert.

## 9. Scenario menu (QA — integrated summary)

> **Count sequencing (read with §11 Blocker 2):** the QA menu as *authored* is **69 scenarios** (the full superset). After the Critic-ruled dedup, the **Docker harness ships ~25 agent-loop scenarios**; the ~46 pure-contract `[direct]` scenarios drop (already covered by `test/run-tests.sh`), and the D-rank-* ranking metrics **migrate to `test/run-tests.sh` as a new RANKING family**. So: **69 authored → ~25 in Docker + a RANKING family in the free per-PR harness.** Report should quote ~25 as the Docker menu size and note the migration, not 69.

Full menu: `plans/e2e-scenarios.md` — **69 scenarios as authored, 8 families** (→ ~25 in Docker post-dedup), each with id / NL prompt / expected agent action / exact oracle / model+cost / flake handling. Load-bearing structure:

- **Two test LAYERS (the key design move):** **[direct]** variants run `sh …/action` with NO `claude -p` — deterministic, ~$0, the regression backbone (46 of 69); **agent-driven** variants pay for `claude -p` to test that a real agent *chooses + drives* the CLI. Every learn/crud/negative family has a cheap direct variant; agent variants sit on top only where "the agent decided" is the value. This cleanly answers the Critic's likely "are you just re-testing the unit harness" challenge — the [direct] layer is explicitly the contract-regression layer, the agent layer is the genuinely new coverage.
- **Two-tier oracle per agent scenario:** a **CHOICE** assertion (agent picked+fired the tool — retry-eligible 2×, since model choice is the non-deterministic part) AND a **BEHAVIOR** assertion (exit code / `tool_result.content` substring / FS state — NEVER retried). Pass requires both; flake is confined to CHOICE. This is the §3b template made operational.
- **Families:** **D** Discovery (8 — the headline; reuses `test/golden` for P@1/@3/MRR/NDCG@5 + adversarial grade-0-not-#1 guard), **L** Load (5), **F** Full loop (4 — search→load→use→**report**→promote; includes F-loop-noreport-negative as the loop-not-closed control), **C** CRUD (14), **LR** Learn (14 — incl. all 5 gotchas + the d8d8ab0 quality-guard WARN), **N** Negative/edge (12 — incl. the exit-1-not-2 missing-patterns gotcha + the mp-load wrinkle), **H** Hooks (5 — direct + live), **I** Install/registration (7 — the image-readiness gates).
- **5 gotchas APPLIED (not just referenced):** missing-patterns→exit1 = N-search-missing-patterns; mv-leaves-empty-dir = LR-promote ("assert on chunk location"); mp-load-exit1-but-prints = N-load-failingpatch-wrinkle; patch-list vs patch-validate = C-patch-add-list-validate; injected-transcript hooks = H-resume-* / LR-harvest-transcript-handshake.
- **P0 smoke set: 13 scenarios** (~10 free [direct] + 3 cheap haiku agent loops ≈ $0.12 total) — image build, registration, discovery choice, ranking quality, load chain, learn gradient, two error paths. Gates every commit; the billed agent lane is `workflow_dispatch`/nightly.
- **Model heuristic:** haiku when one correct tool path ("did it fire + return slug X"); sonnet for judgment-under-ambiguity (lexical traps like D-agent-crossdomain, multi-step chains like F-loop-full, body-consumption, state handshakes).

## 10. Architect-owned open items + cross-doc reconciliations

- **[ARCHITECT — owe a fixture] Pin the ranking baseline.** D-rank-precision/adversarial assert against a baseline P@1/@3/MRR/NDCG@5; I owe one clean run of the ranker over all graded qids to record that baseline fixture so regressions are detectable. Deferred to build phase (needs the image), not a design blocker.
- **[RECONCILE — query-row count] RESOLVED by direct inspection of `test/golden/queries.tsv`:** **119 graded annotation rows across 55 distinct qids** (file is 129 lines = 9 comment lines + 1 header + 119 data rows). Grade distribution: **55 grade-2** (exactly one per qid — matches RUBRIC's "one perfect target per query"), **46 grade-1** (near-miss, for NDCG resolution), **18 grade-0** (adversarial, must-not-rank-#1). The "128" (domain §5) and "120" (QA menu) were both off (line-count arithmetic that mis-subtracted comments/header). **The Report and any doc quoting a number must say "119 rows / 55 queries."** This is the authoritative figure.
- **[RECONCILE — DONE] QA doc's stale opens.** The QA menu's "Open items" still list the `--bare` decision and `Skill`-tool-resolution as open — both are now RESOLVED (§3a-bis, §6, docker §0). QA's `I-skill-tool-sees-skills` scenario remains valuable as a standing image-readiness gate even though the spike itself is closed. The QA `--bare`-caveat language in §0.2 should be read as superseded by §3a-bis.
- **[H-family — highest residual feasibility risk]** Live-hook scenarios (H-nudge-live-session, H-resume-live-clear) depend on hooks being observable + a `SessionStart:clear` being triggerable headlessly with an injected transcript. The **[direct]** hook variants (H-*-direct) are the proven fallback and carry the real assertion weight; live variants are P2 stretch. Confirm with DevOps whether live wiring is in scope or deferred.

---

## 11. Critic stress-test — verdict + architect rulings

The Critic stress-tested the combined design (consolidated verdict, 9 items). Architect rulings below; spikes assigned. **Verdict: sound at the contract level; three items need work before the menu is final.**

### Accepted as-is (Critic READY items)
- **Oracle 5 gotchas** — baked + verified ✓. **`--bare` decision** — RESOLVED (no `--bare`) ✓. **Auth/isolation** — ✓ (DevOps to verify non-auth skill resolution at image build).

### BLOCKER 1 — Feasibility: does "agent chooses to fire mp-search" GENERALIZE? — **ACCEPTED; mitigation LOCKED + spike assigned to QA.**
The headless contract proved the tool-fire loop **once**. The menu assumes it generalizes to ~23 agent-loop scenarios with the risk that "the agent just answers from its own knowledge and never fires the skill" → a scenario that **silently no-ops to a false green**. This is the harness's central risk and gets a **three-part mitigation, all locked before Report:**

1. **Oracle hard-fail on zero tool-calls (design-level, DONE — §3b ANTI-SILENT-NO-OP INVARIANT).** An agent-loop scenario with zero matching `Skill`/`Bash` tool_use events is a FAILURE *by construction* — there is no free-text path to green. A no-fire is a BEHAVIOR-class fail (NOT retry-eligible; it's real signal, not flake). This makes the silent-no-op structurally impossible to pass.
2. **P0 canary scenario (NEW — `I-skill-tool-sees-skills`, already in the P0 smoke set, promoted to explicit CANARY).** It runs a trivial NL prompt post-registration and asserts (a) `init.skills[]` lists the mp dirnames AND (b) a `Skill(search)` tool_use actually fires. If the canary doesn't fire, the **entire agent lane aborts** (the keystone is broken) rather than every downstream scenario flaking independently. One cheap (~$0.04) gate guards the whole lane.
3. **Empirical fire-rate spike (QA, gates finalization).** Drive the ~6 distinct prompt ARCHETYPES (not all 23) 5× on haiku; report % fire-rate per archetype. **<80% fire-rate → strengthen the imperative prompt ("you MUST invoke the X skill") or demote/drop.** Agent-loop scenarios stay **PROVISIONAL** until the spike clears.

Together: #1 guarantees a no-fire can never masquerade as a pass; #2 fails fast at the lane level; #3 measures the real-world rate so prompts are tuned before trust. The team-lead's requested mitigation (oracle hard-fails on zero mp tool-calls + a P0 canary) is exactly #1+#2, now explicit.

### BLOCKER 2 — Duplication with run-tests.sh — **ACCEPTED with a correction; dedup to ~25 Docker scenarios.**
**Architect-verified against `test/run-tests.sh`:** the overlap is real — run-tests.sh already covers search-nomatch→exit1 (L902), empty-patterns→exit1 (L1155), scaffold native+legacy (L1584/1600), promote via status_history, AND a *seed* golden-rubric check (L2411–2517: one graded query, asserts git-rebase in Convergence for q002, asserts queries.tsv present). **Ruling:**
- The ~46 [direct] scenarios that re-test pure CLI contracts **drop from the Docker menu** — they belong in (and mostly already exist in) the free, deterministic, per-PR `test/run-tests.sh`. Running them through Docker adds cost + flake surface for zero new signal.
- **CORRECTION to the Critic:** D-rank-* is NOT pure duplication — run-tests.sh has only a *one-query structural seed*, not the full P@1/@3/MRR/NDCG@5 sweep over 55 qids. So D-rank-* is a **meaningful extension**: migrate it to `test/run-tests.sh` as a new **RANKING family** (deterministic, free, per-PR) — don't just delete it. This also relocates my §10 ranking-baseline-fixture obligation into run-tests.sh where it's cheapest.
- **Result:** Docker menu keeps ONLY agent-loop scenarios (the genuinely new coverage) → 69 → ~25 scenarios; run-level ceiling $5 → ~$3. The Docker harness's *reason to exist* is the real-agent loop; the [direct] backbone was always run-tests.sh's job.

### BLOCKER 3 / DECISION — Live hooks unproven — **RULING: Option A (drop live variants now), with the DevOps spike as a fast-follow.**
H-nudge-live-session / H-resume-live-clear assume Stop/SessionStart fire + are observable in `-p`, and that `:clear` is triggerable headlessly — none verified. **Ruling: Option A.** Ship only the **[direct]** hook variants (H-nudge-direct, H-resume-direct, H-resume-harvest-roundtrip) — they fully cover the hook *logic* (counter increment, threshold nudge, once-guard, atomic pending-transcript write, read-then-unlink). The live variants test *harness wiring*, which is unproven and not worth blocking the deliverable. DevOps still runs the feasibility spike; if it succeeds cleanly, the two live variants can be promoted in a later pass — but they are OUT of the v1 menu. Rationale: the design deliverable's value is the scenario menu + architecture; an unproven-wiring scenario is a liability, and the direct variants already assert the behavior that matters.

### NEEDS REVISION (QA owns; not architect-blocking)
- **#7 Tautological scenarios** — ACCEPTED: L-load-use (substring overlap too fragile → assert a specific command sequence from the loaded chunk), D-agent-3axis-quality (define "3 distinct axes" rigorously + assert Convergence present), F-loop-noreport-negative (keep but mark **[soft]** — it's an inconclusive/control assertion, not a hard gate; do NOT delete — it documents the d8d8ab0 loop-not-closed behavior).
- **#8 Flakiness doctrine** — ACCEPTED: QA tags CHOICE-vs-BEHAVIOR retry-eligibility *per assertion* explicitly (the doctrine exists in §0.6 but isn't applied row-by-row). Run ceiling → ~$3 post-dedup.
- **#9 Exit-code gotcha not tested — ACCEPTED, real gap.** GOTCHA-2 (exit 0 on API failure) is a load-bearing oracle assumption that no scenario validates. **Add `N-oracle-exit-code-unreliable`**: invoke `claude -p` with a bad `--model`, assert process `$?==0` BUT `result.is_error==true` (404/model_not_found), and assert the oracle correctly FAILS the scenario by reading JSON not `$?`. This is a meta-test of the oracle itself — cheap, ~$0.01 (errors before real work), and it's the one scenario that proves our central oracle rule is enforced.

### Spike assignments (gate menu finalization)
1. **QA** — agent-prompt feasibility spike (6 archetypes ×5, report fire-rate) + dedup (drop [direct], migrate D-rank-* to run-tests.sh RANKING family) + oracle tightening (#7/#8/#9).
2. **DevOps** — live-hook feasibility spike (informs whether live variants ever return; does NOT block v1).
3. **Architect** — rulings above recorded; ranking-baseline fixture obligation moves to the run-tests.sh RANKING family.

---

> **Status: Critic integrated; menu finalization gated on 2 spikes (QA feasibility, DevOps hooks).** Harness is contract-sound. Once QA's spike + dedup land and #7/#8/#9 are applied, the design is final → Report.
