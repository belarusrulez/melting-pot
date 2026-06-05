# E2E Headless Contract — driving `claude -p` in Docker

**Author:** headless expert (Wave 1) · **Verified against:** `claude` v2.1.162 (native build, `/Users/coding/.local/bin/claude`), 2026-06-04 · All JSON shapes below are from REAL runs on this machine, not docs paraphrase.

**FEASIBILITY VERDICT: GREEN — with one mandatory design constraint (see §0).** The full loop (prompt → agent invokes mp-search via the `Skill` tool → Bash runs `sh ~/.melt/.../action` → reads result → can chain mp-load/mp-learn) runs headlessly and unattended, and every step is observable in `stream-json`. Two gotchas that will silently break a naive harness are flagged LOUDLY below.

---

## 0. TWO LOUD GOTCHAS (read first — these gate the design)

### GOTCHA 1 — Literal `/search` slash-commands DO NOT execute in `-p` mode
A prompt of `claude -p "/search find a skill"` does **not** run the mp-search skill. It returns a plain clarifying-question text answer with `num_turns:1` and **no** `Skill`/`Bash` tool_use. This matches the official doc note:

> "User-invoked skills like `/code-review` and built-in commands are only available in interactive mode. In `-p` mode, describe the task you want to accomplish instead."

**Consequence:** the harness must drive skills via **natural-language prompts**, not `/skill` syntax. Verified working prompt form:
```
"Use the mp-search skill to find a skill for reviewing code. You MUST invoke the search skill."
```
…which produced `Skill(skill:"search")` → `Bash(sh ~/.melt/search/action …)` → real Convergence output. So the oracle's prompts must be phrased as intents/instructions, and the test should assert the agent *chose* to fire the skill (that choice is itself part of what we're testing).

### GOTCHA 2 — Shell exit code is `0` even on hard API failure
A `--model nonexistent-model-xyz` run returned `is_error:true`, `api_error_status:404`, `result:"There's an issue with the selected model…"` — but the **process exit code was 0**. `claude -p` largely reports failures *in the JSON body*, not via exit status.

**Consequence:** the test oracle MUST parse `result.is_error` / `result.subtype` from `--output-format json`. Do **not** gate pass/fail on `$?` alone. (Exit-code table in §4.)

---

## 0b. Architect follow-ups — RESOLVED empirically (2026-06-04)

### Q2 — Skill identifier: it's the **dirname (`search`)**, NOT the hyphenated `mp-search`
The `Skill` tool's `skill` field is the **registry dirname**. The `system/init` event lists `"skills":[…,"search",…]` and `"slash_commands":[…,"search",…]` — there is **no `mp-search` entry**. Verified: even when prompted *"Invoke the skill named **mp-search**…"*, the agent emitted `Skill(skill:"search")`. The `mp-` prefix (hyphenated frontmatter `name:` → `/mp-search` interactively) does NOT survive into `-p` mode.

**Oracle rule:** assert `tool_use.input.skill == "search"` (and `"load"`, `"learn"`, `"list"` — all bare dirnames). Do **not** assert `"mp-search"`. If a future install registers skills under the `mp-`-prefixed name, the init event's `skills[]` array is the source of truth — an oracle preflight can read it and adapt.

### Q3 — `--json-schema`: co-exists cleanly; tool_use events PRESERVED
Verified with `--json-schema '{…"top_skill","fired_search"…}'` on a full mp-search loop:
- The `Skill` and `Bash` tool_use events **still appear** in the stream — the schema does **not** suppress or alter the tool-call path. (3 tool_use events seen, loop ran normally, `is_error:false`.)
- The `result` object gains a **`structured_output`** field alongside the usual `result` text: `"structured_output": {"fired_search": true, "top_skill": "s:commit"}`. Full result keys now include `structured_output` plus all the normal ones (`is_error`, `permission_denials`, `total_cost_usd`, …).

**So yes — recommend `--json-schema` as the default oracle for ranking-quality scenarios.** Best of both: assert the cheap structured field (`structured_output.top_skill == "s:commit"`, `structured_output.fired_search == true`) AND still cross-check the raw tool_use/tool_result events for ground truth.

**One caveat to design around:** `structured_output` reflects what the *model wrote*, not the raw action output — it's a self-report. In my run the model put `"top_skill":"s:commit"` and its prose agreed, but a buggy/hallucinating model could populate the schema with a value the action never returned. **Therefore: keep the structured field as the convenient primary assertion, but ALWAYS also assert the `tool_result.content` actually contains that slug.** The schema is a convenience layer over the stream, not a replacement for it. (This is just GOTCHA-2 logic applied to structured output: trust the observed tool I/O as ground truth.)

---

## 1. Invocation

Minimal headless call:
```bash
claude -p "<prompt>" --output-format json
```

Recommended CI form for this harness:
```bash
claude --bare -p "<prompt>" \
  --model claude-haiku-4-5-20251001 \
  --output-format stream-json --verbose \
  --allowedTools "Skill,Bash,Read" \
  --permission-mode dontAsk \
  --max-budget-usd 0.25 \
  --no-session-persistence
```

Flag reference (all verified present in v2.1.162 `--help`):

| Flag | Purpose |
|---|---|
| `-p, --print` | Non-interactive: run one prompt, print, exit. stdin is read (pipe-friendly, 10MB cap since v2.1.128). Workspace-trust dialog auto-skipped. |
| `--output-format text\|json\|stream-json` | text = result string only; json = single result object; stream-json = NDJSON event stream. (§3) |
| `--model <id\|alias>` | Pin model. Use full IDs for determinism (e.g. `claude-haiku-4-5-20251001`, `claude-opus-4-8`). |
| `--bare` | **Recommended for CI.** Skips hooks, LSP, plugin sync, auto-memory, CLAUDE.md auto-discovery, keychain. Forces auth to `ANTHROPIC_API_KEY`/`apiKeyHelper`. Same result on every machine. Pass context explicitly via `--add-dir`, `--mcp-config`, `--settings`, etc. **Caveat for us: bare mode skips CLAUDE.md/plugin auto-discovery — confirm mp skills still resolve under `--bare` in the container, or run without `--bare` and instead pin the env. (Open item for Wave 2.)** |
| `--max-budget-usd <amt>` | Hard dollar cap per invocation (only with `--print`). Aborts the run if exceeded. Our per-scenario circuit-breaker. |
| `--no-session-persistence` | Don't write session to disk (only with `--print`). Keeps containers stateless. |
| `--verbose` | Required to get full event stream with `stream-json`. |
| `--include-partial-messages` | Token-level deltas (only stream-json). NOT needed for an oracle that asserts on tool calls; adds noise. |
| `--continue` / `--resume <id>` / `--session-id <uuid>` | Multi-turn. Capture `session_id` from JSON, pass to `--resume`. `--session-id` lets the harness set a known UUID up front. |
| `--fallback-model <m>` | Auto-fallback on overload (only with `--print`). Useful for CI robustness; **but introduces model-variance → leave OFF for determinism tests.** |
| `--max-turns` | **NOT a flag in v2.1.162.** Agentic turn count is bounded by prompt + budget, not a `--max-turns` flag. Use `--max-budget-usd` as the practical cap. (`num_turns` is reported in the result.) |
| `--json-schema '<schema>'` | Force structured output → result lands in `structured_output` field. Great for making oracle assertions trivial (see §6). |

There is **no `--timeout` flag**; wrap the call in shell `timeout`:
```bash
timeout 300 claude --bare -p "…" --output-format json …
```

---

## 2. Tool permissions (no interactive prompts in a container)

Verified: `--allowedTools "Bash(echo*)"` let the agent run `echo HELLO_FROM_BASH` with zero prompting and the command executed.

Three layers, cleanest → most blunt:

1. **`--allowedTools` (RECOMMENDED for this harness).** Permission-rule syntax. For mp skills the agent needs the `Skill` tool plus Bash to run the action script:
   ```
   --allowedTools "Skill,Bash,Read,Write"
   ```
   Tighter Bash scoping is possible — e.g. `"Bash(sh ~/.melt/*)"` / `"Bash(sh *action*)"` — but the action scripts shell out broadly, so start permissive (`Bash`) and tighten in Wave 2 once we see the exact command lines in the stream.

2. **`--permission-mode <mode>`** — verified choices in v2.1.162: `acceptEdits, auto, bypassPermissions, default, dontAsk, plan`.
   - `dontAsk` — denies anything not in `permissions.allow` or the read-only set; **cleanest locked-down CI mode**. Combine with `--allowedTools` to whitelist exactly what the loop needs.
   - `acceptEdits` — auto-approves file writes + common fs commands (mkdir/touch/mv/cp); other shell/network still needs an allow entry.
   - `bypassPermissions` — approves everything (equivalent intent to `--dangerously-skip-permissions`). Use only in a sealed container.

3. **`--dangerously-skip-permissions` / `--allow-dangerously-skip-permissions`** — nuke all checks. Anthropic recommends only for sandboxes with no internet access. **A Docker container with `--network none` for the assertion steps qualifies; acceptable fallback if allowlists prove brittle.**

4. **settings.json `permissions` block** via `--settings <file-or-json>` — declarative `allow`/`deny` arrays; portable into the image. Equivalent to `--allowedTools` but version-controllable.

**Cleanest for CI:** `--permission-mode dontAsk` + explicit `--allowedTools "Skill,Bash,Read,Write"`. Falls back to `--dangerously-skip-permissions` inside a network-isolated container if a skill's action needs something unforeseen. A denied tool does NOT crash the run — it surfaces in `result.permission_denials[]` (empty array when none), so the oracle can assert "nothing was unexpectedly denied."

---

## 3. Observability — JSON shapes (from real runs)

### `--output-format json` (single array of events; last element is the `result`)
The `result` object fields the oracle cares about (real sample):
```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "api_error_status": null,
  "duration_ms": 3163,
  "num_turns": 1,
  "result": "PONG",
  "session_id": "1f6ba81c-…",
  "total_cost_usd": 0.01535975,
  "usage": { "input_tokens": 10, "output_tokens": 120,
             "cache_read_input_tokens": 18060, "cache_creation_input_tokens": 10355 },
  "modelUsage": { "claude-haiku-4-5-20251001": { "costUSD": 0.01535975, … } },
  "permission_denials": [],
  "terminal_reason": "completed"
}
```

### `--output-format stream-json --verbose` (NDJSON, one event per line)
Event sequence for a tool-using turn (verified driving mp-search):

1. `{"type":"system","subtype":"init", "model":…, "tools":[…], "slash_commands":[…], "skills":[…], "permissionMode":…, "apiKeySource":"none", "claude_code_version":"2.1.162", "session_id":…}` — first event; great for asserting the right model/skills/version loaded.
2. `{"type":"system","subtype":"thinking_tokens", …}` — repeated, ignorable.
3. **Tool call:** `{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_…","name":"Skill","input":{"skill":"search","args":"…"}}]}}`
4. **Then:** `{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"sh ~/.melt/search/action \"…\" \"…\" \"…\"","description":"…"}}]}}`
5. **Tool result:** delivered as a `user` message — `{"type":"user","message":{"content":[{"type":"tool_result","content":"## Convergence (matched 2+ axes…)\n  s:audit  axes=3 score=0.2409 …"}]}}`
6. `{"type":"assistant","message":{"content":[{"type":"text","text":"Search found strong hits…"}]}}`
7. `{"type":"result", …}` (same shape as json mode).

**Oracle recipe:** stream lines through `jq`/Python; assert:
- a `tool_use` event with `name=="Skill"` and `input.skill=="search"` exists (skill was *chosen*),
- a following `tool_use` `name=="Bash"` whose `input.command` contains `~/.melt/search/action` (action *fired*),
- the matching `tool_result.content` contains the expected skill row (e.g. `s:audit`, `axes=3`) (action *returned the right skill*),
- final `result.is_error==false` and `result.permission_denials==[]`.

This gives the exact "mp-search actually fired and returned skill X" assertion the architect asked for. Verified end-to-end: `num_turns:4`, `total_cost_usd:0.0344` on haiku.

---

## 4. Exit codes

| Situation | Process exit | JSON `result` |
|---|---|---|
| Successful run | `0` | `is_error:false`, `subtype:"success"` |
| Model not found / API error | **`0` (!!)** | `is_error:true`, `api_error_status:404`, `subtype:"success"` (misleading subtype), event carries `error:"model_not_found"` |
| Tool denied (run still completes) | `0` | `is_error:false`; denial recorded in `permission_denials[]` |
| Budget exceeded (`--max-budget-usd`) | non-zero (abort) | run aborts; treat as failure |
| stdin > 10MB | non-zero | clear error |
| Bad CLI flags / usage | non-zero | — |

**RULE: never trust exit code alone for API/agent-level failures.** Always parse `is_error`. Reserve exit-code checks for crash/usage/budget/timeout classes. Wrap in `timeout` so a hang → non-zero (124).

---

## 5. Auth in a container

- This machine: `ANTHROPIC_API_KEY` **unset**, no `~/.claude/.credentials.json` — auth is via **macOS keychain (OAuth subscription)**, shown as `"apiKeySource":"none"` in init. **Keychain is NOT portable into a Linux container.**
- **Container path = `ANTHROPIC_API_KEY` env var.** Pass it in (`docker run -e ANTHROPIC_API_KEY=…` / CI secret). With `--bare`, this is the *only* accepted Anthropic auth (OAuth/keychain never read) — clean and explicit for CI. Alternative: `apiKeyHelper` in `--settings` JSON.
- First-run state: a writable `~/.claude` (or `$CLAUDE_CONFIG_DIR`). With `--bare --no-session-persistence` the footprint is minimal — no plugin/CLAUDE.md discovery, no session files. Still ensure `$HOME` is writable so the CLI can create its dirs. Seed nothing else; no login step needed when `ANTHROPIC_API_KEY` is set.
- **The mp skills live at `~/.melt/` and are installed via the repo's bootstrap.** The container image must run that install so `~/.melt/<skill>/action` and `~/.melt/repos.patterns` exist, AND the skills must be registered as Claude Code skills so the `Skill` tool can launch them. (Verify under `--bare`, which skips plugin/skill auto-discovery — may need to run *without* `--bare`, or explicitly point at the skill dir. Wave-2 image item.)
- **Cost note (real numbers, haiku):** trivial PONG ≈ \$0.015; full mp-search loop (4 turns) ≈ \$0.034. Budget on the order of **\$0.03–0.10 per scenario on haiku**, more on opus. Set `--max-budget-usd 0.25` as a per-scenario breaker. **NOTE (billing change):** per the official doc, *starting 2026-06-15* `claude -p` on subscription plans draws from a separate monthly Agent SDK credit — for CI prefer a dedicated `ANTHROPIC_API_KEY` (pay-as-you-go) so test spend is isolated and metered.

---

## 6. Determinism / flakiness

Sources of non-determinism:
- LLM sampling (no `--temperature` flag exposed; sampling is non-zero) → wording of `text`/`result` varies run to run.
- Agentic path variance: the model may take a different number of turns or phrase the action args differently.
- `--fallback-model` swapping models mid-run.
- Local config bleed (hooks, CLAUDE.md, plugins, MCP servers) changing behavior between machines.
- The caveman plugin was active in these runs and altered output style ("caveman mode") — **proves local config bleed is real; `--bare` or a clean `$CLAUDE_CONFIG_DIR` is needed to neutralize it.**

Knobs to reduce it:
- **Pin `--model` to a full version ID** (not `opus`/`sonnet` alias).
- **`--bare`** (or a pristine `CLAUDE_CONFIG_DIR`) to eliminate hook/plugin/CLAUDE.md bleed — this is also what killed reproducibility here (caveman mode).
- Do **not** use `--fallback-model` in determinism-sensitive scenarios.
- Constrain the task so there's essentially one correct tool path; keep prompts tightly scoped and budget low.
- Prefer `--json-schema` to force structured output → assert on stable fields instead of free-text.

What the oracle should TOLERATE (assert on structure, not prose):
- Exact `result` wording — DON'T assert.
- Tool was invoked with the right name + the action script path in the command — DO assert.
- Tool result CONTAINS the expected skill slug / axis count — DO assert (substring/regex, not equality).
- `is_error==false`, `permission_denials==[]`, model in init matches expected — DO assert.
- `num_turns`/cost within a sane band — soft-assert/log, don't hard-fail on small drift.

---

## 7. Feasibility verdict (expanded)

**YES — reliably drivable headless + unattended, given the design constraints.** Proven on this machine end-to-end: a natural-language prompt caused the agent to invoke `Skill(search)` → `Bash(sh ~/.melt/search/action …)` → return real Convergence output, with the entire chain observable in `stream-json`.

Blockers / must-handle, in priority order:
1. **[GATING] No `/slash` skills in `-p`** — harness must prompt in natural language and assert the agent *chose* to fire the skill. (§0.1)
2. **[GATING] Exit code unreliable** — oracle MUST parse `is_error` from JSON, not `$?`. (§0.2, §4)
3. **[IMAGE] Auth** — container needs `ANTHROPIC_API_KEY`; keychain/OAuth won't travel. (§5)
4. **[IMAGE] Skill install + registration under the chosen mode** — `~/.melt` must be installed AND skills registered so the `Skill` tool sees them; confirm whether `--bare` hides them (it skips skill auto-discovery). Decide bare-vs-clean-config in Wave 2. (§1, §5)
5. **[QUALITY] Determinism** — pin model, neutralize local config (caveman mode bled in here), assert on structure not prose. (§6)
6. **[COST/BILLING] Budget per scenario** (~\$0.03–0.10 haiku) and the 2026-06-15 subscription→Agent-SDK-credit change → use a dedicated API key for CI. (§5)

No hard blockers. The remaining unknowns (bare vs full config for skill resolution) are container-build details for Wave 2, not feasibility risks.
