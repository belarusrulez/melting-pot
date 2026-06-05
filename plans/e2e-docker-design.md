# E2E Docker Design — container + harness lifecycle

**Author:** DevOps / Docker engineer (Wave 2) · **Builds on:** [`e2e-headless-contract.md`](./e2e-headless-contract.md) (CLI/headless) + [`e2e-groundtruth-contract.md`](./e2e-groundtruth-contract.md) (domain). All `claude`-behaviour claims below were re-verified on this host against `claude` v2.1.162 (2026-06-04). Snippets are illustrative sketches — this is a design, not finished build code.

---

## 0. THE #1 SPIKE — RESOLVED (do NOT use `--bare`)

**Question (from architect):** does the `Skill` tool see mp skills under `claude -p --bare` (which skips skill discovery) vs needing a clean `$CLAUDE_CONFIG_DIR` *without* `--bare`?

**Verdict: use a clean `$CLAUDE_CONFIG_DIR` WITHOUT `--bare`.** Verified empirically (the `system/init` event is emitted *before* auth, so these probes ran even on this keychain-only host with no API key):

| Mode | `init.skills[]` contains `search,list,crud,load,learn`? |
| --- | --- |
| **No `--bare`**, `CLAUDE_CONFIG_DIR=/clean/dir` with each `mp/<skill>/` symlinked into `<dir>/skills/<skill>` | **YES — all 5 present** in both `skills[]` and `slash_commands[]` |
| **`--bare`**, same config dir | **NO — all 5 vanish**; only builtin skills (deep-research, code-review, …) remain |

The `--bare` help line *"Skills still resolve via /skill-name"* refers to **builtin** skills baked into the binary — **not** personal `$CLAUDE_CONFIG_DIR/skills/` skills. `--bare` skips personal-skill discovery, which is exactly the mechanism mp relies on. **So `--bare` is off the table for any scenario that fires an mp skill.**

This is *fine* — the headless contract recommended `--bare` only for determinism, and a clean `$CLAUDE_CONFIG_DIR` delivers the same determinism without the skill-blindness:

- Verified with a pristine `CLAUDE_CONFIG_DIR`: `mcp_servers: []`, **no caveman/user-plugin bleed** (the exact bleed §6 of the headless contract flagged), `permissionMode` honoured, only mp skills + the unavoidable builtins. We control the entire dir, so nothing leaks in.
- The only residue is the builtin skill set shipped inside the `claude` binary (`deep-research`, `code-review`, `simplify`, `verify`, `run`, …). They are inert for our scenarios — the oracle asserts `tool_use.input.skill == "search"` (etc.), never "no other skills exist". They cannot be removed (binary-internal) and need no handling.

**How the container registers mp skills (the answer to "how does a headless agent find+fire them"):** during image build / fixture seed, for each `mp/<skill>/` (which contains `SKILL.md`), create `$CLAUDE_CONFIG_DIR/skills/<skill>` pointing at it (symlink on Linux; copy if a layer needs to be writable). This *is* INSTALL.md step 4 ("register every `SKILL.md` as a personal skill"), done the Claude-Code-native way. After that, `claude -p` (no `--bare`) sees `search/list/crud/load/learn` and the agent can `Skill(skill:"search")` → `Bash(sh $MP_HOME/search/action …)`.

> **Note the two distinct symlink sets — don't conflate them:**
> 1. `$CLAUDE_CONFIG_DIR/skills/<skill>` → `mp/<skill>/` — makes the **`Skill` tool** see the skill (registration; gates whether the agent can *choose* it).
> 2. `$MP_HOME/<skill>/action` → `mp/<skill>/action` — makes `sh $MP_HOME/<skill>/action` resolve when the agent runs **Bash** (this is what `install.sh` creates).
> Both are required for the full loop. The first is the spike's answer; the second is the existing installer's job.

**Auth caveat surfaced by the spike:** a clean `CLAUDE_CONFIG_DIR` has no credentials. On this host (keychain OAuth, no `ANTHROPIC_API_KEY`) a *billed* turn returned `is_error:true, result:"Not logged in · Please run /login", cost:0`. In the container this is solved by injecting `ANTHROPIC_API_KEY` (§2). The init-event probes still succeeded because init is pre-auth — which is why the spike was answerable here at all.

> **FAST-FOLLOW (not a Report gate) — Linux-container reconfirm.** Every spike above ran on the macOS dev host (keychain, BSD utils). The shipping target is `debian:bookworm-slim` (glibc, dash, GNU coreutils). The one untested assumption is "macOS-host skill-visibility == Linux-container behavior." Once the image is built (build phase, not this design deliverable), the CLI expert re-runs the same pass condition **inside the container**: `init.skills[]` contains `search,list,crud,load,learn` (no `--bare`) and they vanish under `--bare`. This probe is pre-auth and free; it upgrades "verified on dev host" to "verified in the shipping image." Owned by DevOps to hand off the image; CLI expert owns the Linux-container run. Separate from the auth'd end-to-end `Skill`-fires + `Stop`-on-success batched run (also pending, needs an API key).

---

## 1. Base image + dependencies (pinned)

**Base:** `debian:bookworm-slim` (`debian:12.5-slim` digest-pinned). Glibc (the native `claude` build expects it — alpine/musl risks subtle breakage), small, predictable coreutils. Pin by digest in the real Dockerfile.

```dockerfile
FROM debian:bookworm-slim@sha256:<pin>      # debian 12

# --- system deps, pinned via apt snapshot or explicit versions ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq sqlite3 \
      coreutils findutils \
   && rm -rf /var/lib/apt/lists/*
# sqlite3 in bookworm is 3.40.x — FTS5 compiled in (verify: see RUN check below).
```

| Dep | Why | Pin / verify |
| --- | --- | --- |
| **Claude Code CLI v2.1.162** | the SUT; native build, must match the version both contracts were verified against | install the **native** distribution, pin to `2.1.162`. Verify `claude --version` == `2.1.162 (Claude Code)` in a build-time `RUN` (fail the build otherwise). |
| **sqlite3 (≥3.20, FTS5)** | `mp-search` index is FTS5 (`search/action`); FTS5 is mandatory | bookworm ships 3.40.x. Build-time assert: `sqlite3 :memory: 'CREATE VIRTUAL TABLE t USING fts5(x);'` must exit 0, else fail the build. (INSTALL.md §Platform calls this out.) |
| **git** | `mp_apply_in_memory` seeds a tmp git work-tree and runs `git apply --check` (`patch.sh`); patch scenarios need it | bookworm git 2.39.x; pin acceptable. |
| **sh + coreutils** | all 5 actions are POSIX-sh; `discover/tier/patch/compose.sh` use standard utils | debian `dash` is `/bin/sh`; actions are `#!/bin/sh`-clean (already CI-tested cross-platform per recent commits). |
| **jq** | oracle parses `stream-json` / structured-output in shell; lighter than python for line-by-line | pin bookworm jq 1.6 (Python 3.11 also present for richer oracle assertions — pick one; sketches below use jq). |
| **python3** (optional) | richer oracle scoring (NDCG/MRR over the golden corpus) is far easier in Python than jq | bookworm python3.11; only if the scoring oracle lives in-container. |

**Claude Code install:** use the official native installer pinned to the exact version, e.g.
```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | sh -s -- 2.1.162 \
 && ln -sf "$HOME/.local/bin/claude" /usr/local/bin/claude \
 && claude --version | grep -qx '2.1.162 (Claude Code)'
```
*(Exact installer URL/flags to be confirmed against Anthropic's published install method at build time; the load-bearing part is **pin 2.1.162 and assert it**. A newer CLI can change `stream-json` shapes both contracts depend on.)*

Run as a **non-root `melt` user** with a writable `$HOME` (the CLI must create dirs under `$CLAUDE_CONFIG_DIR`/`$HOME`).

---

## 2. Auth + secrets + cost breaker

**Auth — `ANTHROPIC_API_KEY` only, never baked:**
- Inject at run via `docker run -e ANTHROPIC_API_KEY` (local) or BuildKit secret mount / CI secret env (CI). **Never** `ENV ANTHROPIC_API_KEY=` and never `COPY` a creds file — that bakes it into a layer.
- A clean `$CLAUDE_CONFIG_DIR` has no `.credentials.json` and keychain/OAuth don't exist in Linux, so `ANTHROPIC_API_KEY` is the sole auth path (matches headless contract §5). Verified failure mode without it: `result:"Not logged in"`.
- **Billing isolation:** per the 2026-06-15 subscription→Agent-SDK-credit change (headless §5), use a **dedicated pay-as-you-go key** for CI so test spend is metered separately. Store as `ANTHROPIC_API_KEY` repo secret.

**Cost breaker — layered:**
1. `--max-budget-usd 0.25` per `claude -p` invocation (per-scenario circuit breaker; aborts the run, non-zero exit → oracle treats as failure). Headless real numbers: PONG ≈ \$0.015, full mp-search loop ≈ \$0.034 on haiku → 0.25 is ~7× headroom, generous but bounded.
2. **Run-level ceiling** in the harness: sum reported `total_cost_usd` across scenarios; abort the suite if it crosses a configured cap (~\$3 — the post-dedup Docker menu is ~25 agent-loop scenarios × ≈\$0.10 + headroom). Cheap insurance against a runaway matrix.
3. **`--model claude-haiku-4-5-20251001`** pinned for cost + determinism.

> **Scope note (architecture §11, Critic Blocker 2):** the post-dedup Docker menu is **agent-loop-only** (~25 scenarios). The ranking-quality scenarios (`D-rank-*`) migrated **out of Docker** into the free per-PR `test/run-tests.sh` harness — they don't need a real agent, just the CLI. So inside Docker the `--json-schema` ranking-oracle technique (below) and any "hard ranking" subset are no longer exercised here; they live in the unit harness. This doc's Docker lifecycle is therefore tuned for the loop tier.

**Determinism / config neutralization (the clean-config recipe, replacing `--bare`):**
- Set `CLAUDE_CONFIG_DIR=$RUN/cfg` to a dir the harness builds — containing ONLY `skills/<skill>` symlinks + a minimal `settings.json` (permissions block, no hooks unless a hook scenario wants them). Nothing from any host `~/.claude` leaks in.
- Pin `--model` (full ID, never alias). Do **not** use `--fallback-model` in determinism scenarios (model variance).
- Result: verified `mcp_servers:[]`, no plugin/caveman bleed, only mp + builtin skills.

---

## 3. Fixture seeding

Two overlays per scenario, both built from the repo checkout `COPY`d into the image at a fixed path (`/opt/melting-pot`):

**A. Claude-Code registration overlay (`$CLAUDE_CONFIG_DIR`):**
```sh
# built per RUN (ephemeral); makes the Skill tool see mp skills
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
for d in /opt/melting-pot/mp/*/; do
  s=$(basename "$d"); [ -f "$d/SKILL.md" ] || continue
  ln -s "$d" "$CLAUDE_CONFIG_DIR/skills/$s"          # registration (spike answer #1)
done
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{ "permissions": { "allow": ["Skill","Bash","Read","Write"], "defaultMode": "dontAsk" } }
JSON
```

**B. melting-pot runtime overlay (`$MP_HOME`) — via the real installer:**
```sh
export MP_HOME="$RUN/melt" MP_PATTERNS="$RUN/melt/repos.patterns"
sh /opt/melting-pot/install/install.sh            # seeds $MP_HOME, links each <skill>/action, copies hooks, emits manifest + task-intake
# seed the registered layer at the golden corpus (domain contract §5):
printf '%s\t*\n' "/opt/melting-pot/test/skills" > "$MP_PATTERNS"
sh "$MP_HOME/search/action" reindex                # build FTS5 index over the 79-skill corpus
sh "$MP_HOME/list/action" --count                  # smoke: expect 79
```
`install.sh` is deterministic and asserts the Q-003 invariant (never touches harness config) — safe to run unattended; exit 4 means a breach (fail seeding).

**Manual registration steps the installer can't script (REGISTER-HOOKS.md / INSTALL.md steps 4,6,7) — the harness performs them in-container:**
- *Skill registration* → overlay A above (symlinks into `$CLAUDE_CONFIG_DIR/skills/`).
- *Hooks* → only when a hook scenario needs them: translate the two manifest rows into `$CLAUDE_CONFIG_DIR/settings.json` `hooks.Stop` (`melt-nudge.sh`) and `hooks.SessionStart` matcher `clear` (`melt-resume.sh`). For most scenarios leave hooks OUT (determinism + the headless contract runs effectively bare-equivalent).
- *task-intake.md* → append `$MP_HOME/task-intake.md` to a `CLAUDE.md` passed via `--add-dir` ONLY for scenarios testing intake behaviour; omit otherwise (it changes agent behaviour).

**Scenario-specific seeds (domain §5):**
- *Mutation* (promote/demote): `sh $MP_HOME/crud/action scaffold <name>` → overlay-born native skill with a tier-0 chunk; assert moves without touching the corpus.
- *Patch / `.failed`*: drop a known-bad + known-good `patches/NNN-*.patch` under an overlay skill; reindex; assert `patches_failed=1` and `learn patch-triage`.
- *Hook handshake*: ship a fixture `.jsonl` transcript; call `melt-resume.sh <path> <uuid>`; assert `learn/.pending-transcript` then `learn harvest` read-then-unlink.

---

## 4. Lifecycle (per scenario)

```
build image (once)  ──►  run container (per scenario, ephemeral)
                              │
   ┌──────────────────────────┼──────────────────────────────────────────┐
   │ 1. SEED   mk $RUN/{cfg,melt}; overlay A (skills symlinks)            │
   │           install.sh → $MP_HOME; repos.patterns→test/skills;        │
   │           reindex; scenario-specific seed (scaffold / patches / …)  │
   │ 2. RUN    claude -p "<intent prompt>"  (NO --bare)                   │
   │             --model claude-haiku-4-5-20251001                        │
   │             --output-format stream-json --verbose                   │
   │             --allowedTools "Skill,Bash,Read,Write"                   │
   │             --permission-mode dontAsk                                │
   │             --max-budget-usd 0.25 --no-session-persistence           │
   │             [--json-schema <schema>]  < /dev/null                    │
   │           wrapped in `timeout 300` (no --timeout flag exists)        │
   │ 3. COLLECT  $RUN/run.ndjson (transcript), $MP_HOME tree (state),     │
   │             $MP_HOME/search/index.db, stderr, exit code              │
   │ 4. ASSERT   oracle parses ndjson + filesystem (see below)            │
   │ 5. TEARDOWN rm -rf $RUN  (or drop the whole container)               │
   └────────────────────────────────────────────────────────────────────┘
```

**Invocation (final, NOT `--bare`):**
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
> Always redirect `< /dev/null` — verified that without it the CLI waits 3s for stdin ("no stdin data received in 3s"). Adds latency, not a failure, but close it.

**Oracle assertions (both contracts):**
- Parse `stream-json` (jq/python). Assert: a `tool_use name=="Skill" input.skill=="search"` exists (skill *chosen*); a following `tool_use name=="Bash"` whose `input.command` contains `$MP_HOME/.../search/action` (action *fired*); matching `tool_result.content` contains the expected slug (e.g. `s:audit`, `axes=3`) (right skill *returned*).
- **Never trust exit code for API/agent failure** (headless §0.2/§4): the final `result.is_error` is the source of truth. Reserve `$?` for crash/usage/budget/timeout (timeout→124). `result.permission_denials == []`.
- Cross-check filesystem state against domain contract §0/§2 (chunk moved tier, `status_history` appended append-only, `.failed` marker's 4 sections, `.pending-transcript` consumed).
- For any *agent-loop* scenario where the agent self-reports a chosen skill, `--json-schema` (`structured_output.top_skill`, `fired_search`) is a convenient primary assertion, but **always** also assert the raw `tool_result.content` (structured output is a model self-report — GOTCHA-2 logic). (Pure ranking-quality scoring now lives in `test/run-tests.sh`, not here — see the scope note in §2.)
- Tolerate prose variance; assert on structure/substring, soft-log cost & `num_turns` drift.

**Isolation tradeoff — recommend ephemeral-per-scenario:**

| | Per-scenario container | Per-run container, fresh `$RUN` dir per scenario |
| --- | --- | --- |
| Isolation | Strongest (kernel-level fresh FS, no cross-bleed) | Strong enough — each scenario gets its own `$CLAUDE_CONFIG_DIR`+`$MP_HOME`; only the OS layer is shared |
| Speed | Container start per scenario (~1s) ×N | One start; seed/teardown per scenario in-process |
| Cost/CI | More container churn | Fewer Docker invocations |

**Recommendation:** **per-run container, per-scenario `$RUN` directory** (`mktemp -d`). The state contracts hinge on `$MP_HOME`/`$CLAUDE_CONFIG_DIR` being scenario-private, and pointing those at a fresh `mktemp -d` per scenario gives full state isolation without paying container-start N times. Reserve full per-scenario containers only for a scenario that must mutate something outside `$RUN` (none identified yet). Each scenario MUST set its own `CLAUDE_CONFIG_DIR`, `MP_HOME`, `MP_PATTERNS` env (domain contract §intro: "set MP_HOME/MP_PATTERNS to a sandbox path per scenario").

**Network:** the agent turn needs network (Anthropic API). Assertion/seeding steps don't — but since they run in the same container, keep network ON for the run and rely on `--permission-mode dontAsk` + `--allowedTools` to bound tool use. (If a future hardening pass wants `--network none` for assertion-only steps, split them into a second exec after the API turn — the headless contract notes a network-isolated container is the sanctioned home for `--dangerously-skip-permissions` as a fallback if allowlists prove brittle.)

---

## 5. CI story (GitHub Actions)

```yaml
name: e2e-headless
on: [workflow_dispatch]          # MANUAL by default — these runs cost money + hit the API
jobs:
  e2e:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Build (cached)
        uses: docker/build-push-action@v6
        with:
          context: .
          tags: melt-e2e:2.1.162
          cache-from: type=gha
          cache-to:   type=gha,mode=max          # cache the heavy CLI+apt layer
          load: true
      - name: Run scenarios
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY_E2E }}   # dedicated PAYG key
          MELT_RUN_BUDGET_USD: "3.00"   # ~25 loop scenarios x ~$0.10 + headroom
        run: |
          docker run --rm \
            -e ANTHROPIC_API_KEY -e MELT_RUN_BUDGET_USD \
            melt-e2e:2.1.162 \
            /opt/melting-pot/test/e2e/run-scenarios.sh
      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: e2e-transcripts
          path: /tmp/e2e-artifacts/**     # ndjson transcripts + collected $MP_HOME state + index.db
```

- **Trigger:** `workflow_dispatch` (manual) + optional nightly `schedule` — **not** on every PR (cost + API dependency). A cheap non-billed lane (the existing `test/run-tests.sh`, 98 tests) stays on every PR; the billed e2e lane is gated.
- **Image caching:** GHA cache (`type=gha`) on the CLI+apt layer (the slow part). Image tag carries the pinned CLI version so a CLI bump busts the cache intentionally.
- **Cost guards:** dedicated PAYG `ANTHROPIC_API_KEY_E2E` secret (billing isolation post-2026-06-15); per-scenario `--max-budget-usd 0.25`; run-level `MELT_RUN_BUDGET_USD` ceiling (~\$3 for the ~25-scenario loop menu) summed from each result's `total_cost_usd`, abort if crossed.
- **Flaky / API-down handling:**
  - *API unreachable / overloaded* (`api_error_status` 429/5xx, or timeout 124): **SKIP, not FAIL** — emit a neutral/skipped result so an Anthropic outage doesn't red the build. Distinguish from genuine assertion failures (which FAIL).
  - *Model-not-found / 404 / auth*: hard **FAIL** (config error, our fault).
  - *Budget exceeded*: **FAIL** (a scenario that should cost \$0.03 hitting \$0.25 is a real regression).
  - *Assertion mismatch* (wrong skill, marker missing, denial): **FAIL**.
  - Light **retry** (1 retry) only for the transient class (429/5xx/timeout) before declaring skip.
  - Always upload `run.ndjson` + collected state as artifacts (`if: always()`) so a failure is debuggable post-hoc.

---

## 5b. Hook-firing spike — RESOLVED (2026-06-04, empirical; Critic-flagged risk)

> **Architect ruling (recorded architecture §11): Option A — the two live-hook variants (H-nudge-live-session, H-resume-live-clear) are DROPPED from the v1 menu;** the direct variants (H-nudge-direct, H-resume-direct, H-resume-harvest-roundtrip) carry the hook-*logic* assertion weight. This spike is a **FAST-FOLLOW** that can *promote* the live variants in a later pass — it is not a v1 gate. The findings below stand and already largely de-risk that future promotion. The `clear`-is-interactive-only finding (Q2) directly supports Option A: the live `clear` wiring genuinely can't be exercised headlessly without a matcher accommodation, so deferring it is the right call.

The live-hook scenarios assumed hooks fire + are observable in headless `-p`. Verified against `claude` v2.1.162 with evidence-writing probe hooks wired into `$CLAUDE_CONFIG_DIR/settings.json` (`--include-hook-events`). Even on this auth-less host the answers are conclusive (hook firing for `SessionStart` is independent of the model turn):

**Q1 — Do hooks fire in `-p` mode, and is their output observable? → YES (both).**
- `SessionStart` fired (proven by disk evidence AND stream events). With `--include-hook-events` the stream carries `{"type":"system","subtype":"hook_started",…}` then `{"subtype":"hook_response", "hook_name":"SessionStart:startup", "stdout":"…", "stderr":"…", "exit_code":0, "outcome":"success"}`. **`hook_response.stdout` is a fully structured assertion surface** — an oracle reads the nudge/resume text straight from it. (Belt-and-suspenders: hooks also write `$MP_HOME/learn/.tool-count-*` / `.pending-transcript`, so firing is assertable on disk regardless of stream.)
- Hooks receive **JSON on stdin**: `{session_id, transcript_path, cwd, hook_event_name, source}`. This is how a Claude-Code-native wrapper feeds the harness-agnostic mp hooks (which read positional args / env, not stdin JSON — see Q3 wrapper).

**Q2 — Can `SessionStart:clear` be triggered headlessly? → NO. The `clear` matcher is interactive-only.** Reachable `SessionStart` sources in `-p`: **`startup`** (fresh `-p` run) and **`resume`** (`--resume <id>`). `clear` corresponds to the interactive `/clear` command (confirmed: `clear` exists in the binary only as a keyboard/UI action, never a `-p`-reachable source). **Consequence:** the H-resume-live-clear scenario as written (matcher `clear`) **cannot fire under `-p`**. Two viable rewrites (no need to drop it):
  - **(preferred) bind `melt-resume` to the `resume` source** in the test image's `settings.json` (matcher `resume` or empty), then drive it with `claude -p --resume <prior-session-id>`. `--resume` IS a `-p` flag and fires `SessionStart:resume` — verified. The hook's *logic* (write `.pending-transcript` from a transcript path) is identical regardless of which source triggers it, so this faithfully exercises the live handshake.
  - **(alt) `startup` source on a session whose transcript path is the prior run's** — also fires, same logic.
  The matcher difference (`clear` in production vs `resume`/`startup` in test) is a test-rig accommodation, not a behaviour change — call it out in the scenario so it's not mistaken for testing the production `clear` wiring. The production `clear` binding itself is only exercisable in the interactive direct-variant (H-resume-direct), which already covers it.

**Q3 — Session-ID timing. → Available before the hook fires.** The `SessionStart` hook's stdin JSON already contains `session_id` + `transcript_path` at fire time, and the same `session_id` appears in the `init` event. So `.tool-count-<sess>` / `.session-nudged-<sess>` keying is satisfiable. The Claude-Code→mp wrapper:
```sh
# settings.json hooks.SessionStart[].hooks[].command — parses stdin JSON, feeds the harness-agnostic mp hook
sh -c 'j=$(cat); sh "$MP_HOME/hooks/melt-resume.sh" "$(printf %s "$j"|jq -r .transcript_path)" "$(printf %s "$j"|jq -r .session_id)"'
```
Verified end-to-end against a sample stdin: the wrapper extracted the path + id and `melt-resume.sh` wrote `$MP_HOME/learn/.pending-transcript` correctly. (`melt-nudge.sh` for `Stop` takes the session id the same way: `$1`/`MP_SESSION_ID`.)

**REMAINING HONEST GAP — `Stop` on a *successful* turn not yet observed.** `Stop` did **not** fire in my run, but the run auth-failed (`is_error:true`, "Not logged in") so no turn ever completed — `Stop` fires at *turn end*, and there was no turn end. I could not close this on an auth-less host. **What to confirm with an API key (cheap, one billed PONG turn):** that a successful `-p` turn emits `Stop` and thus `hook_response` for `melt-nudge`. My strong expectation is YES (the hook machinery, stdin JSON, and `--include-hook-events` plumbing all demonstrably work for `SessionStart`; `Stop` uses the identical path), but it is **unverified**. The headless expert has an API key and offered hands — this is the ideal hand-off (one trivial billed run). **Verdict for the menu:** H-nudge-live-session is **feasible pending this one confirmation**; if `Stop` somehow doesn't fire in `-p`, fall back to H-nudge-direct (the hook is harness-agnostic and fully testable by invoking it directly with a session id + threshold). H-resume-live-* is feasible now via the `resume`-source rewrite (Q2).

**Net for the Critic:** live-hook scenarios are feasible — keep them, with two adjustments: (1) `melt-resume` live scenario uses the `resume`/`startup` source, not `clear`; (2) `melt-nudge` live scenario carries a one-billed-turn `Stop`-fires confirmation as a prerequisite (hand to headless expert). Assertion surface = `hook_response` events in the `--include-hook-events` stream + the on-disk `$MP_HOME/learn/` markers. Neither scenario is blocked; nothing needs dropping.

---

## 6. Ambiguities the contracts left open (flagged for architect)

1. **Claude Code native installer URL/pinning** — INSTALL/contracts don't pin an install command. I assert-pin `2.1.162` but the exact native-installer invocation must be confirmed at build time (Anthropic's published method). Load-bearing: pin + assert version; a CLI bump changes `stream-json` shapes both contracts depend on.
2. **Hooks in-scenario by default?** — headless contract leans bare-equivalent (no hooks); domain contract has explicit hook scenarios needing `melt-nudge`/`melt-resume` wired into `settings.json`. I default hooks OFF and turn them ON only for the hook-handshake scenarios. Confirm that split is the intended scope. **(Feasibility now resolved — see §5b: hooks DO fire + are observable in `-p`; one `Stop`-on-success confirmation outstanding.)**
3. **task-intake.md injection** — appending it to a `CLAUDE.md` changes agent behaviour (forces the rephrase-×3 + mp-search-first intake). Good for an "intake-loop" scenario, noise for a focused "did search fire" scenario. I inject it only for intake scenarios. Confirm.
4. **`--network none` for assertion steps** — desirable for hardening but requires splitting the API turn from assertion into separate `docker exec`s. Deferred unless the architect wants it now.
5. **Oracle language (jq vs python)** — golden-corpus NDCG/MRR scoring (domain §5) is far cleaner in Python; pure tool-fired/state assertions are fine in jq. I'd ship both interpreters and let scoring oracles use Python. Confirm acceptable image weight.
6. **Builtin-skill noise** — the binary ships ~12 builtin skills (deep-research, code-review, …) that can't be removed from `init.skills[]`. Harmless (oracle asserts specific slugs) but worth noting so an oracle never asserts "exactly 5 skills exist".
