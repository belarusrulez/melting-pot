# test/e2e — agent-loop e2e harness

Drives the melting-pot skill CLIs through **real `claude -p` headless runs** to
prove a live agent *chooses + fires* the right skill (not just that the CLI
works — that's `test/run-tests.sh`). Design: [`../../plans/e2e-test-plan.md`](../../plans/e2e-test-plan.md).

## Files

| File | Role |
|---|---|
| `scenarios.tsv` | P0 smoke scenarios: `id  model  skill  substr  prompt` (TAB-sep) |
| `seed.sh` | Seeds one scenario sandbox: clean `$CLAUDE_CONFIG_DIR` (skill symlinks → `Skill` tool sees them) + `~/.melt` via real `install.sh` + golden corpus + reindex |
| `run-scenarios.sh` | Loops scenarios → `claude -p` (stream-json, no `--bare`) → `oracle.sh`. Runs identically on host and in-container |
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

## Status

- **Built + green:** P0 smoke set (`I-canary`, `D-agent-synonym`, `L-load-basic`) — 3/3
  pass both host and Docker (verified `claude` 2.1.165, 2026-06-05).
- **Pending:** the wider ~25-scenario agent menu (F-loop / CRUD / Learn / Negative /
  Hooks families), the formal fire-rate spike, and the GitHub Actions workflow —
  see `plans/e2e-test-plan.md` §8.
