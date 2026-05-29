# melting-pot — LLM-in-the-loop test plan

> Goal: validate that a real LLM, given a vague user task, correctly invokes `mp:search` (3-axis), picks the right skill, and (optionally) reads its SKILL.md. The 97 shell tests already validate the mechanics. These tests validate the **agent-in-the-loop** contract.

## Status

- [ ] Plan approved
- [ ] Phase A: smoke runner shipped (1 query, asserts claude responds + Bash tool fires)
- [ ] Phase B: golden subset shipped (4 queries from `test/golden/queries.tsv`, asserts top-hit dirname)
- [ ] Phase C: rubric grading (loop 10 queries; compute precision@1; assert ≥ threshold)
- [ ] Phase D: end-to-end (claude picks skill → reads SKILL.md → emits a plan; assert plan mentions expected tool/command)

This plan covers **Phase A + Phase B** for v1. Phases C + D are deferred.

---

## 1. Scope

### In scope (v1)
- Single-file standalone runner: `test/run-llm-tests.sh`
- 4 queries from `test/golden/queries.tsv` covering all three categories (exact-vocab, synonym-jargon, intent-only).
- Per-query assertion: claude's final response contains the **expected target dirname** from the rubric.
- Sandboxed `$MP_HOME` per test (no pollution of `~/.melt/`).
- Cost gate: per-test `--max-budget-usd 1.00`; total run capped at $4 max.
- Opt-in: not part of `sh test/run-tests.sh`. Run via `sh test/run-llm-tests.sh`.
- Skip cleanly when (a) `claude` CLI missing, (b) `MP_LLM_TESTS=1` env not set, (c) auth fails.

### Out of scope (deferred)
- Adversarial-grade-0 anti-patterns (catch ranker that returns grade-0 at #1). → Phase C
- Precision@N / NDCG metrics over the full 39-query rubric. → Phase C
- Multi-step flows: search → load → apply. → Phase D
- CI integration. → after Phase C proves stability.
- Cross-model parity (Opus vs Sonnet vs Haiku). → Phase D

---

## 2. Model selection

Default: **`claude-sonnet-4-6`** via `--model` flag.

Rationale:
- ~5× cheaper than Opus ($3 vs $15 input / $15 vs $75 output).
- Tool-use accuracy on a single-step skill-pick is well within Sonnet's capability.
- Opus expensive for what is essentially a "run command + parse output" task.

Override via env: `MP_LLM_TEST_MODEL=claude-opus-4-7 sh test/run-llm-tests.sh`.

### Cost model
- Sonnet 4.6 per query: ~500 input tok prompt + ~1 Bash tool call (~80 input tok return) + ~10 output tok answer + system prompt overhead.
- Rough per-query cost: **~$0.03–$0.05** (Sonnet) / **~$0.15–$0.30** (Opus).
- 4-query Phase B run: **~$0.20** (Sonnet) / **~$1.00** (Opus).

Hard cap: `--max-budget-usd 1.00` per `claude -p` invocation. Per-test caps stop runaway loops.

---

## 3. Query selection (Phase B)

Four queries from `test/golden/queries.tsv`. Categories balanced; targets correspond to existing fixtures under `test/skills/`.

| qid | category | task (axis3) | target dirname | grade-0 distractor |
|---|---|---|---|---|
| q001 | exact-vocab | "find which commit introduced the regression" | `git-bisect` | `flake-rerun` |
| q012 | exact-vocab | "turn this password into the right form for a Secret yaml" | `base64-codec` | `qr-make` |
| q007 | synonym-jargon | "figure out when this regression appeared" | `git-bisect` | `git-rebase` |
| q015 | intent-only | "figure out where all my disk space went" | `disk-usage-top` | — |

q001 and q007 both target `git-bisect`, but the LLM is given **different axes** for each — q001 uses exact vocab ("binary search the first bad commit"), q007 uses synonym ("find the commit that broke this"). If both hit, the ranker handles lexical and semantic signal.

q012 specifically tests adversarial: `qr-make` shares lexical surface ("base64 / encode / k8s manifest" overlap is low; the actual distractor is more subtle in the corpus). If the LLM returns `qr-make`, the test catches a ranking bias.

---

## 4. Fixture setup (per-test)

Each test is hermetic:

```sh
TDIR=$(mktemp -d -t mp-llm.XXXXXX)
export MP_HOME="$TDIR/melt"
export MP_PATTERNS="$MP_HOME/repos.patterns"
mkdir -p "$MP_HOME"
printf "%s\t%s\n" "$ROOT/test/skills" "*" > "$MP_PATTERNS"
sh "$ROOT/mp/search/action" reindex >/dev/null
```

Then invoke `claude -p` (claude subprocess inherits `$MP_HOME` + `$MP_PATTERNS`).

Cleanup: `rm -rf "$TDIR"` on exit (trap).

---

## 5. Prompt design

Single prompt template, one substitution: the user's task (axis3 from `queries.tsv`).

```
You have a 3-axis skill search tool at:
  /Users/coding/Projects/melting-pot/mp/search/action

It takes three positional args (literal, synonym, intent) and prints
skill matches in a "Convergence" section (top of output) followed by
"Single-axis hits".

USER TASK: <task>

Run the search tool with three rephrasings of the task (literal, synonym,
intent). After the tool returns, output ONLY the dirname of the top
skill in the Convergence section. No quotes, no commentary, no path —
just the dirname (e.g. "git-bisect").
```

### Why this shape

- **Explicit tool path** — we're testing the search-tool flow, not whether claude *independently discovers* `mp:search`. Discovery is a separate concern (separate test class, Phase D).
- **"Output ONLY the dirname"** — assertion is exact-match on response trim. No JSON parsing fragility.
- **"Top in Convergence"** — locks the assertion to the strongest-signal section, not the full ranked list.

### Tool permissions

- `--dangerously-skip-permissions` — sandbox env, no user prompt for Bash approvals.
- `--add-dir /Users/coding/Projects/melting-pot` — gives claude file access to the action script.
- Allowed tools: `Bash` only. No need for Read/Edit; the search action prints to stdout.

---

## 6. Assertion logic

```sh
expected="git-bisect"
response=$(claude -p \
  --model "$MP_LLM_TEST_MODEL" \
  --dangerously-skip-permissions \
  --max-budget-usd 1.00 \
  --add-dir "$ROOT" \
  --allowedTools "Bash" \
  "$prompt" 2>&1 | tail -1 | tr -d '[:space:]')

if [ "$response" = "$expected" ]; then
  pass "LLM-Q001"
else
  fail "LLM-Q001" "expected=$expected got=$response"
fi
```

### What we accept

- **Exact dirname match** on last non-blank line of claude's output. Lenient: `tr -d '[:space:]'` strips trailing newlines.
- No partial credit. If claude says "git-rebase" for a q001 query, that's a fail.

### What we reject

- Multi-line responses with commentary (the prompt says "ONLY the dirname"; if claude ignores that, test fails — that's a real signal).
- Quoted dirname (`"git-bisect"`) — same: prompt says no quotes. We could strip them but won't; instruction-following is part of the contract.

---

## 7. Failure modes + how we handle

| Failure | Reason | Handling |
|---|---|---|
| `claude` CLI not in PATH | Test environment | `skip` all LLM tests with note |
| `MP_LLM_TESTS=1` not set | Opt-in gate | `skip` (silently) |
| Auth failure (`/login` prompt) | OAuth keychain unavailable | `skip` with message |
| `--max-budget-usd` exceeded | Prompt loops / model verbose | Report as test fail with budget-exceeded reason |
| Network down / API 5xx | Anthropic outage | Report as fail; consider retry-once for transient errors |
| Sonnet/Opus answers something plausible-but-wrong | Real bug or genuine model variance | Real fail. Logged. May need rubric refinement (Phase C). |
| Tool call hangs >60s | Likely runaway | Wrap in `timeout 90 ...`; treat as fail |

---

## 8. Integration with main suite

- **Not** added to `test/run-tests.sh`. The main suite stays 97/97 deterministic shell tests.
- New file `test/run-llm-tests.sh` lives alongside, opt-in.
- Same output shape: `PASS LLM-Q001` / `FAIL LLM-Q001 — reason`. Same pass/fail/skip counters. Same exit code semantics (0 = all pass, 1 = any fail).
- `MP_LLM_TESTS=1` env var required to actually run; without it the script skips everything and exits 0.

---

## 9. File layout

```
test/
├── run-tests.sh                # main suite (untouched)
├── run-llm-tests.sh            # NEW — Phase A + Phase B runner
├── llm/                        # NEW
│   ├── prompt.tmpl             # prompt template (one file, used by all queries)
│   └── queries.tsv             # subset of golden/queries.tsv (4 rows for v1)
├── skills/                     # corpus (existing)
└── golden/                     # rubric + full queries.tsv (existing)
```

Why `test/llm/queries.tsv` rather than reading from `test/golden/queries.tsv` directly:
- Decouples LLM-test subset from grading rubric. We can add/remove LLM queries without churning rubric.
- Makes Phase C migration explicit (Phase C would merge the two).

---

## 10. Open questions

### Q-L01 · Where is the API budget coming from?

User OAuth quota or `ANTHROPIC_API_KEY`? Default behavior pulls from claude-code's auth. Should `run-llm-tests.sh` document a `MP_LLM_API_KEY` override?

**v1 default:** inherit from claude-code's existing auth. No new env var.

### Q-L02 · Sonnet 4.6 vs Opus 4.7 default?

Sonnet is 5× cheaper. Opus more reliable on edge-case wording.

**v1 default:** Sonnet 4.6. Override via `MP_LLM_TEST_MODEL`.

### Q-L03 · How aggressive on the assertion?

Exact-match is brittle. Could allow case-insensitive, or "expected appears anywhere in last 3 lines."

**v1 default:** exact-match on trimmed last line. Phase C may relax with NDCG.

### Q-L04 · Retry on transient failures?

Network blip or rate limit could fail a test that would otherwise pass.

**v1 default:** no retry. If you want CI stability, wrap the runner in a shell `for retry in 1 2 3; do ...; done`. Phase C decision.

### Q-L05 · Should adversarial queries be a separate test class?

Right now we lump "must return X" with "must not return Y" in the same test. Phase C may want explicit `must_not_be` assertions.

**v1 default:** rely on rubric — if test returns a grade-0 distractor, that's a fail by definition (it's not the expected target).

---

## 11. Verify-now plan (after build)

```sh
cd /Users/coding/Projects/melting-pot

# 1. Confirm claude CLI works (one-shot smoke, ~$0.05)
MP_LLM_TESTS=1 sh test/run-llm-tests.sh LLM-SMOKE

# 2. Full Phase B run (4 queries, ~$0.20 Sonnet / ~$1.00 Opus)
MP_LLM_TESTS=1 sh test/run-llm-tests.sh

# 3. Try Opus for comparison (~$1.00)
MP_LLM_TESTS=1 MP_LLM_TEST_MODEL=claude-opus-4-7 sh test/run-llm-tests.sh

# 4. Run a single query
MP_LLM_TESTS=1 sh test/run-llm-tests.sh LLM-Q012
```

Expected: 5/5 PASS (1 smoke + 4 queries) within ~2 minutes total. Failures log the expected-vs-got + the claude response transcript.

---

## 12. Decision points for the user (before I implement)

1. **Model default**: Sonnet 4.6 (cheap, recommended) or Opus 4.7 (expensive but max accuracy)?
2. **Query count**: 4 (this plan) or more / fewer?
3. **Budget cap per test**: $1.00 (this plan) or different?
4. **Skip rule**: opt-in via `MP_LLM_TESTS=1` (this plan) or always-on (just costs money)?
5. **Phase A smoke test**: yes (1 cheap query proves claude+budget works before spending on Phase B) or no (jump straight to Phase B)?
