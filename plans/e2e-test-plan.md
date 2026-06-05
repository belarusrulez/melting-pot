# melting-pot Docker E2E Test Plan — canonical, signed-off

> **Status: DESIGN COMPLETE — signed off.** This is the single user-facing plan
> for a docker-based e2e harness that drives the five melting-pot skill CLIs
> through **real `claude -p` headless runs**. No harness code is shipped yet
> (`## Pending` tracks what build delivers). It consolidates and supersedes the
> four supporting docs as the canonical reference:
> - `plans/e2e-architecture.md` — master integration + Critic rulings (§11).
> - `plans/e2e-headless-contract.md` — what's drivable/observable in `claude -p`.
> - `plans/e2e-groundtruth-contract.md` — per-CLI exit codes, mutated state, golden corpus.
> - `plans/e2e-docker-design.md` — container, auth, lifecycle, CI.
> - `plans/e2e-scenarios.md` — the full scenario menu (per-row prompts + oracles).
>
> All `claude`-behaviour claims were verified against `claude` v2.1.162 on the
> dev host, 2026-06-04. All corpus counts re-verified against the repo this turn.

---

## 1. What this harness is (and is NOT)

The existing **`test/run-tests.sh`** (free, deterministic, per-PR) already covers
the `mp/lib/*` layer and pure-CLI behaviour against a sandboxed `$MP_HOME` and the
golden corpus. It does **not** run a real agent.

This harness fills the one gap that unit tests cannot: the **real-agent loop** —
a natural-language prompt → `claude -p` *chooses* to fire an mp skill → runs the
`action` script → reads the result → does work → reports use → `mp-learn` moves a
chunk. The value is *"a real agent CHOSE and DROVE the CLI correctly,"* not
re-testing CLI contracts.

**In scope:** discovery actually firing, the right skill picked (graded against
`test/golden`), the promotion gradient actually moving, hooks firing, and image
registration of skills + hooks.

**Out of scope (owned by `test/run-tests.sh`):** `mp/lib/*` unit behaviour, pure
exit-code matrices, tier math, in-memory patch-apply mechanics.

---

## 2. Resolved key decisions (locked)

| # | Decision | Why |
|---|---|---|
| **No `/slash` in `-p`** | Prompts are **natural language** ("Use the search skill to…; you MUST invoke it"); the oracle asserts the agent *chose* to fire it. Never `claude -p "/search …"`. | `/slash` skills are interactive-only; in `-p` they return plain text, no tool call. (headless §0.1) |
| **Parse `is_error`, not `$?`** | The oracle reads `result.is_error` from JSON. `$?` is trusted ONLY for crash / usage / budget / `timeout`(124). | A model-not-found API failure exits the process `0` with `is_error:true` in the body. (headless §0.2, §4) |
| **No `--bare`** | Agent scenarios run **without `--bare`**, with a pristine `$CLAUDE_CONFIG_DIR`. | `--bare` skips personal-skill discovery → all 5 mp skills VANISH from `init.skills[]`. A clean config dir gives the same determinism (`mcp_servers:[]`, zero plugin/caveman bleed) *without* the skill-blindness. (architecture §3a-bis, §6; docker §0) |
| **Dirname identifiers** | Oracle asserts `tool_use.input.skill == "search"` (and `load`/`learn`/`list`/`crud`) — the **bare dirname**, never `"mp-search"`. | Confirmed empirically: even prompted "invoke mp-search", the agent emits `Skill(skill:"search")`; `init.skills[]` lists bare dirnames. An oracle preflight MAY read `init.skills[]` as the source of truth. (architecture §3a; headless §0b-Q2) |
| **Two distinct symlink sets** | (1) `$CLAUDE_CONFIG_DIR/skills/<skill>` → `mp/<skill>/` makes the `Skill` tool *see* the skill; (2) `$MP_HOME/<skill>/action` → repo action makes `Bash` *run* it. Both required for the loop. | (1) is INSTALL.md step 4 done Claude-Code-native; (2) is `install.sh`'s job. (architecture §3a-bis; docker §0) |
| **`--json-schema` co-exists** | Recommended *convenience primary* for ranking scenarios (`structured_output.top_skill`) — but ALWAYS cross-check raw `tool_result.content`. | The schema does NOT suppress tool_use events, but `structured_output` is the model's self-report; observed tool I/O is ground truth. (headless §0b-Q3) |

### 2a. ANTI-SILENT-NO-OP INVARIANT (the harness's central safety property)

The single most dangerous failure mode is an agent that **answers from its own
knowledge and never fires the mp skill** — a scenario that would "pass" by
free-text inspection while testing nothing. The harness makes this a **HARD FAIL
by construction**: an agent-loop scenario with **zero matching `Skill`/`Bash`
tool_use events is a FAILURE, never a pass** — there is no free-text path to
green. The oracle asserts `count(Skill where input.skill==<dirname>) >= 1` AND
the paired `Bash(action)` fired; absent either → FAIL. A no-fire is a
**BEHAVIOR-class failure (NOT retry-eligible)** — it is real signal, not flake.
(architecture §3b)

Backed by a three-part mitigation, all locked:
1. **Oracle hard-fail on zero tool-calls** — design-level, makes silent-no-op structurally impossible to pass.
2. **P0 CANARY (`I-skill-tool-sees-skills`)** — if the keystone (`init.skills[]` lists mp dirnames AND `Skill(search)` fires) doesn't hold, the **entire agent lane aborts** rather than every downstream scenario flaking independently.
3. **Empirical fire-rate spike** (see §8 Pending) — drive the ~6 prompt archetypes ×5 on haiku; <80% fire-rate → strengthen the imperative prompt or demote/drop. Agent scenarios stay PROVISIONAL until this clears.

---

## 3. Universal oracle template

Parse `--output-format stream-json --verbose` (NDJSON). A scenario PASSES iff:
- **chose:** a `tool_use` `name=="Skill"`, `input.skill==<expected dirname>` exists;
- **fired:** a following `tool_use` `name=="Bash"` whose `input.command` contains the action path (e.g. `~/.melt/search/action`);
- **right result:** the matching `tool_result.content` contains the expected substring (slug / `axes=N` / chunk path);
- **clean:** final `result.is_error==false` AND `result.permission_denials==[]`;
- **state (mutation scenarios):** the expected `$MP_HOME` filesystem change (chunk location, appended `status_history`, `.failed` marker, `.pending-transcript`).
- **TOLERATE:** exact prose, `num_turns`/cost drift (soft-log only). Assert on STRUCTURE / substrings, never free text.

**Two-tier assertion per agent scenario:** a **CHOICE** assertion (agent picked +
fired the tool — retry-eligible **2×**, since model choice is the
non-deterministic part) AND a **BEHAVIOR** assertion (exit code /
`tool_result.content` substring / FS state — **never retried**). Pass requires
both; flake is confined to CHOICE.

### 3a. Five oracle-biting gotchas (baked into assertions)

1. **Missing `repos.patterns` ⇒ search/list exit `1` (no hits), NOT `2`.** Auto-reindex builds a valid empty index. Only `list-roots`/`doctor` return `2` for missing config.
2. **promote/demote use `mv` and leave the empty source tier dir behind.** Assert on chunk *location* + appended `status_history`, NEVER on dir absence. Demote at tier 0 = `rm -f` after cascade-flagging dependents.
3. **`mp-load` on a mix-origin skill (overlay = patches-only) with a failing patch exits `1` while still printing the composed doc.** Drive `.failed` marker creation via reindex/clean overlay, not via load's exit status.
4. **`patch-list` (marker-based) vs `patch-validate` (real dry-run apply) DISAGREE before any marker exists:** list=`not-yet-attempted`, validate=`failed`. Both read-only.
5. **Hooks need the harness to inject the live transcript path / session id** or `melt-resume.sh` writes nothing.

---

## 4. Harness architecture — container, auth, lifecycle

Full design: `plans/e2e-docker-design.md`. Load-bearing decisions:

**Container.** Base `debian:bookworm-slim` (glibc — the native `claude` build
needs it), digest-pinned. Deps: `git`, `jq`, `python3` (golden-corpus NDCG/MRR/P@k
scoring), `sqlite3` ≥3.40 (FTS5 — build-time assert `CREATE VIRTUAL TABLE … fts5`),
coreutils. **Pin + build-time-assert `claude` `2.1.162`** (a CLI bump can change the
`stream-json` shapes both contracts depend on). Non-root `melt` user, writable `$HOME`.

**Invocation (final — NO `--bare`):**
```sh
timeout 300 claude -p "$PROMPT" \
  --model claude-haiku-4-5-20251001 \
  --output-format stream-json --verbose \
  --allowedTools "Skill,Bash,Read,Write" \
  --permission-mode dontAsk \
  --max-budget-usd 0.25 \
  --no-session-persistence \
  < /dev/null > "$RUN/run.ndjson" 2> "$RUN/run.err"
```
`[--json-schema …]` added for ranking scenarios. Always redirect `< /dev/null`
(else the CLI waits 3s for stdin). There is no `--timeout`/`--max-turns` flag —
wrap in shell `timeout`.

**Seeding = two overlays per scenario:**
- **(A) Registration** — `$CLAUDE_CONFIG_DIR/skills/<skill>` symlinks + minimal `settings.json` (permissions; hooks only if needed). Lets the `Skill` tool see the skills.
- **(B) Runtime** — `$MP_HOME` via the real `install.sh` + `repos.patterns → test/skills` + `reindex` + smoke `list --count == 79`. Lets Bash run the actions.

**Isolation.** **Per-RUN container, per-scenario `mktemp -d`** for
`$CLAUDE_CONFIG_DIR`/`$MP_HOME`/`$MP_PATTERNS` — full state isolation without
paying N container starts. Each scenario MUST set its own env.

**Auth.** `ANTHROPIC_API_KEY` injected only, never baked (no `ENV`/`COPY` of
creds). A clean config dir has no keychain/OAuth, so the env key is the sole auth
path. Use a **dedicated pay-as-you-go key** for CI (subscription→Agent-SDK-credit
split lands **2026-06-15** — isolate test spend).

**Collect.** Persist `run.ndjson` + `$MP_HOME` tree + `index.db` + stderr/exit out
of the container (the assertion surface; survives teardown).

---

## 5. The scenario MENU

Full menu with per-row prompts + oracles: `plans/e2e-scenarios.md`.

### 5a. The key design move — two LAYERS

- **`[direct]`** — run `sh …/action` with **no `claude -p`**: deterministic, ~$0. This is the CLI-contract regression backbone and **belongs in `test/run-tests.sh`, not Docker** (running them through a container adds cost + flake for zero new signal).
- **agent-driven** — pay for `claude -p` to test that a real agent *chooses + drives* the CLI. **This is the Docker harness's reason to exist.**

After the Critic dedup ruling (architecture §11 BLOCKER 2): the pre-dedup menu was
**69 scenarios across 8 families**; the **~46 `[direct]` scenarios drop from the
Docker menu** (migrated to / already covered by `test/run-tests.sh`), leaving the
**~25 agent-loop scenarios** the Docker harness actually runs. Run-level ceiling
trimmed $5 → **~$3**.

> **Migration, not deletion — the RANKING family.** `D-rank-precision` /
> `D-rank-adversarial` are a *meaningful extension*, not pure duplication
> (`run-tests.sh` has only a one-query structural seed, not the full
> P@1/@3/MRR/NDCG@5 sweep over 55 qids). They **move to `test/run-tests.sh` as a
> new deterministic, free, per-PR RANKING family** — and the ranking-baseline
> fixture obligation moves there too.

### 5b. The families (Docker agent-loop scenarios)

| Family | Stresses | Flagship Docker (agent) scenarios |
|---|---|---|
| **D — Discovery** (the headline) | `mp-search` | **D-agent-exact** (P0; exact-vocab → `git-bisect`), **D-agent-synonym** (jargon, no literal overlap), **D-agent-crossdomain** (sonnet; lexical trap "rebase shards" ≠ `git-rebase`), **D-agent-intent**, **D-agent-3axis-quality** (asserts a `## Convergence` section formed — proves 3 distinct axes fused). Graded against `test/golden` (P@1/@3/MRR/NDCG@5 + adversarial grade-0-not-#1 guard). |
| **L — Load** | `mp-load` (+search) | **L-load-basic** (P0; search→load composed body), **L-load-native-nomanifest** (meta.md-only), **L-load-use** (sonnet; the loaded autosquash chunk's exact `--fixup`+`--autosquash` sequence must drive the answer). |
| **F — Full loop** (integration headline) | search→load→use→**report**→promote | **F-loop-full** (sonnet; assert chunk moved `0→1-melting-pot/` + `status_history` +1), **F-loop-scaffolded** (haiku; overlay-born skill), **F-loop-demote**, **F-loop-noreport-negative** (**[soft]** control — documents the loop-NOT-closed behaviour from commit `d8d8ab0`; assert NO `learn` call + tier unchanged). |
| **C — CRUD** | `mp-crud` | **C-agent-scaffold** (agent mints a native skill), **C-agent-patch** (sonnet; patch against upstream, `reg→mix`). |
| **LR — Learn** | `mp-learn` | **LR-agent-triage** (agent triages a broken patch), **LR-agent-harvest-roundtrip** (sonnet; hardest — multi-step state handshake: harvest → Read `.jsonl` → harvest `--apply`). |
| **N — Negative/edge** | error paths | **N-agent-nomatch** (agent handles a no-hit gracefully, does NOT hallucinate a skill), **N-oracle-exit-code-unreliable** (meta-test: bad `--model` → `$?==0` BUT `is_error:true` → oracle correctly FAILs by reading JSON — proves the central oracle rule). |
| **H — Hooks** | `melt-nudge`/`melt-resume` | **H-nudge-direct**, **H-resume-direct**, **H-resume-harvest-roundtrip** (the `[direct]` variants carry the hook-logic weight). Live variants are dropped from v1 (see §6). |
| **I — Install/registration** | `install.sh` + registration | **I-skill-tool-sees-skills** (P0 **CANARY** — gates the whole agent lane). Image-readiness `[direct]` gates (I-install-fresh, I-register-then-discover) live in `run-tests.sh`. |

### 5c. P0 smoke set — 13 scenarios, ≈ $0.12 total

Gates every commit. ~10 free `[direct]` (image build, Q-003 invariant,
registration, scaffold, validate, the learn gradient, two error paths, ranker
quality) + **3 cheap haiku agent loops** (≈ $0.04 each): **I-skill-tool-sees-skills**
(the CANARY), **D-agent-exact** (agent CHOOSES to search), **L-load-basic** (agent
chains search→load). The billed agent lane runs `workflow_dispatch`/nightly.

### 5d. Model heuristic

**haiku** when one correct tool path ("did it fire + return slug X"); **sonnet**
for judgment-under-ambiguity (lexical traps like D-agent-crossdomain, multi-step
chains like F-loop-full, body consumption, state handshakes).

---

## 6. Ground truth — the golden corpus

`test/golden/` + `test/skills/` is a ready-made relevance benchmark (groundtruth §5).

- **Corpus:** `test/skills/` — **79 skills** [verified]. Mostly legacy single-`SKILL.md` distractors; two native fixtures (`git-rebase`, `melting-pot-native-demo`) exercise the post-Q-007 tier layout and are the promotion-loop targets.
- **Graded queries:** `test/golden/queries.tsv` — **119 graded data rows across 55 distinct qids** [verified this turn: 129 file lines = 9 comment lines + 1 header + 119 data rows]. Grade distribution: **55× grade-2** (one perfect target per qid), **46× grade-1** (near-miss, for NDCG resolution), **18× grade-0** (adversarial, must-NOT-rank-#1). Metrics: precision@1, precision@3, MRR, NDCG@5.

> **Authoritative figure: "119 rows / 55 queries."** Earlier drafts quoting "128"
> or "120" mis-subtracted comments/header and are superseded.

---

## 7. Cost + CI story

- **Per-scenario breaker:** `--max-budget-usd 0.25` (≈7× the ~$0.034 a real haiku mp-search loop costs).
- **Run-level ceiling:** `$MELT_RUN_BUDGET_USD` ≈ **$3** post-dedup, summing each result's `total_cost_usd`; abort if crossed.
- **CI:** GitHub Actions `workflow_dispatch` + optional nightly `schedule` — **NOT per-PR** (cost + API dependency). The free `test/run-tests.sh` stays per-PR. GHA layer cache on the heavy CLI+apt layer; the image tag carries the pinned CLI version (a bump busts the cache intentionally). Always upload artifacts (`if: always()`).
- **Failure taxonomy:** API-unreachable / 429 / 5xx / `timeout`(124) → **SKIP** (1 light retry first, so an Anthropic outage doesn't red the build); model-404 / auth / budget-exceeded / assertion-mismatch → **FAIL**.

---

## 8. Pending / fast-follow (NOT done)

These are explicitly **not yet built or resolved** — separated from the locked
design above per repo doc conventions.

- **[x] P0 smoke lane BUILT + GREEN (2026-06-05).** `test/e2e/` ships `Dockerfile`, `seed.sh`, `run-scenarios.sh`, `oracle.sh`, `run.sh`, `scenarios.tsv`. The 3 P0 agent scenarios (`I-canary`, `D-agent-synonym`, `L-load-basic`) pass **3/3 on both host and Docker** via real `claude -p` (`claude` 2.1.165, ≈$0.11). **Auth correction:** this account uses a **subscription OAuth token** (`CLAUDE_CODE_OAUTH_TOKEN`), not `ANTHROPIC_API_KEY` — `run.sh` reads it from the macOS keychain and injects at run time (never baked). `--max-budget-usd` is therefore inert (no per-token billing); bound cost by scenario count + `timeout` instead.
- **[ ] Wider agent menu** — the remaining ~22 scenarios (F-loop full/demote, CRUD scaffold/patch, Learn triage/harvest, Negative, Hooks) are designed (§5b) but not yet added to `scenarios.tsv`.
- **[ ] GHA workflow** — `test/e2e/` runs locally; the `workflow_dispatch`/nightly CI lane (docker §5) is not wired yet.
- **[ ] QA fire-rate spike (gates agent-menu finalization)** — drive the ~6 prompt archetypes ×5 on haiku, report % fire-rate per archetype. <80% → strengthen prompts or demote/drop. Agent-loop scenarios stay **PROVISIONAL** until this clears.
- **[ ] Pin the ranking baseline fixture** — one clean run of the ranker over all 55 qids to record baseline P@1/@3/MRR/NDCG@5 so regressions are detectable. Now lands in the `run-tests.sh` RANKING family (needs the image / a built scorer).
- **[ ] Live-hook variants — DEFERRED to a later pass.** `H-nudge-live-session` / `H-resume-live-clear` are **OUT of v1** (Critic ruling, architecture §11 BLOCKER 3). The DevOps spike (docker §5b) already de-risks promotion: hooks DO fire + are observable in `-p` via `--include-hook-events`; `SessionStart:clear` is interactive-only so the live resume variant must bind to the `resume`/`startup` source instead; one outstanding confirmation — that `Stop` fires on a *successful* billed turn (the spike host was auth-less). If that confirms, the two live variants can be promoted.
- **[ ] Future harvest — a test-design skill.** These five docs encode reusable test-design knowledge (the anti-silent-no-op invariant, the direct-vs-agent layering, the two-tier CHOICE/BEHAVIOR oracle, the `is_error`-not-`$?` rule). Worth harvesting into an mp skill so future test design reuses it. (Noted pot-skill gap.)

---

> **Sign-off:** Harness is contract-sound; the ~25 agent-loop menu, the P0 smoke
> set, auth/lifecycle/CI, and the anti-silent-no-op invariant are locked.
> Remaining items in §8 are build-phase work + one feasibility spike, none of
> which block the design deliverable.
