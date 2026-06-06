# test/e2e — agent-loop e2e harness

Drives the melting-pot skill CLIs through **real `claude -p` headless runs** to
prove a live agent *chooses + fires* the right skill (not just that the CLI
works — that's `test/run-tests.sh`). Design: [`../../plans/e2e-test-plan.md`](../../plans/e2e-test-plan.md).

## Files

| File | Role |
|---|---|
| `scenarios.tsv` | P0 smoke scenarios: `id  model  skill  substr  prompt` (TAB-sep) |
| `seed.sh` | Seeds one scenario sandbox: clean `$CLAUDE_CONFIG_DIR` (skill symlinks → `Skill` tool sees them) + `~/.melt` via real `install.sh` + golden corpus + reindex |
| `run-scenarios.sh` | Loops `scenarios.tsv` → `claude -p` (stream-json, no `--bare`) → `oracle.sh`. Runs identically on host and in-container |
| `feature-tests.sh` | Agent-loop coverage for the rest of the features (list, crud validate, trash/restore, learn promote/demote/triage/refactor/harvest, negative) — each a fresh sandbox + fixture + oracle |
| `lifecycle-test.sh` | Full value loop across two sessions (create → bot saves → fresh session discovers) |
| `oracle.sh` | Two-tier assert: CHOICE (`Skill(skill==X)` + `Bash .../X/action` fired) + BEHAVIOR (`is_error==false`, expected substring). Zero tool-calls = HARD FAIL (anti-silent-no-op). Exit 2 = transient → SKIP |
| `Dockerfile` | `debian:bookworm-slim` + git/jq/sqlite3(FTS5)/bash + pinned `claude` CLI + repo. Auth injected at run, never baked |
| `run.sh` | Host driver: reads OAuth token from macOS keychain, runs `--host` or `--docker` |

## Auth

This account uses a **subscription OAuth token** (not an API key). `run.sh` reads
it from the keychain (`claude-oauth-token`) and injects `CLAUDE_CODE_OAUTH_TOKEN`
at run time. Store it once:

```sh
security add-generic-password -a "$USER" -s claude-oauth-token -w   # paste token at prompt
```

Never bake the token into the image or commit it. `ANTHROPIC_API_KEY` also works
if set (CI path).

## Run

```sh
sh test/e2e/run.sh --host                     # run on this host (sandboxed)
sh test/e2e/run.sh --docker                   # build image + run inside container
sh test/e2e/run.sh --host ONLY="I-canary"     # one scenario
```

Cost ≈ $0.03–0.05 per haiku scenario; the P0 set (3) ≈ $0.11.

## Lifecycle test — the full value loop

`lifecycle-test.sh` proves the end-to-end melting-pot loop across **two separate
real `claude -p` sessions sharing one persistent pot**:

1. **CREATE** new infra (Acme Edge deploy via `acmectl`).
2. **SAVE** — session 1: a real agent harvests it into the pot (`crud scaffold` +
   writes the tier-0 chunk). "the bot discovers + saves it".
3. **DISCOVER** — session 2 (a *fresh* session, distinct `session_id`, no shared
   context) runs `search` and finds the skill session 1 saved.

The point: session 2 has zero conversational memory of session 1 — the only path
for the skill to surface is that the knowledge **persisted in the pot**. The test
also asserts the two `session_id`s differ, so discovery can't be memory bleed.

```sh
CLAUDE_CODE_OAUTH_TOKEN=$(security find-generic-password -a "$USER" -s claude-oauth-token -w) \
  sh test/e2e/lifecycle-test.sh           # ~$0.12, two haiku turns
```

## Status

- **Built + green:** P0 smoke set (`I-canary`, `D-agent-synonym`, `L-load-basic`) — 3/3
  pass both host and Docker (verified `claude` 2.1.165, 2026-06-05).
- **Built + green:** `lifecycle-test.sh` — create → bot-saves → fresh-session-discovers,
  passes on host (2026-06-05). Session 1 fired `crud` and scaffolded the skill;
  session 2 (distinct session id) fired `search` and got it back as the top hit.
- **Built + green:** `feature-tests.sh` — 9/9 on host (2026-06-05): list, crud
  validate, crud trash/restore, learn promote(+1), learn demote(−1), patch-triage,
  refactor, harvest, negative. State mutations verified (tier moves, transcript
  consumed, restore).

## Finding: `crud` and `learn` are `disable-model-invocation: true`

Those two skills are NOT meant to be invoked via the `Skill` tool — the agent
should run their `action` directly via Bash. Observed: an agent sometimes
**refuses outright** ("the learn skill is disabled, I can't invoke it") instead of
just running the command, when the prompt says "invoke the skill". Mitigations
applied: (1) the oracle keys the anti-silent-no-op invariant on the **Bash action
firing**, not the `Skill` tool call (robust for both skill kinds); (2) prompts for
these skills say "run its action directly in your shell". A project-side
improvement worth considering: have these `SKILL.md`s explicitly tell the agent to
run the action via Bash rather than attempt a `Skill` invocation.
- **Pending:** the wider ~25-scenario agent menu (F-loop / CRUD / Learn / Negative /
  Hooks families), the formal fire-rate spike, and the GitHub Actions workflow —
  see `plans/e2e-test-plan.md` §8.
