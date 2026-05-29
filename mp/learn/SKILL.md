---
name: mp:learn
description: Lifecycle automation for melting-pot chunks and patches. Use when the user says "harvest reusable techniques", "what should I save from this session", "promote this chunk", "demote that chunk", "clean up stale chunks", "refactor overlapping chunks", "evaluate promote/demote rules", "run lifecycle sweep", "triage failed patches", or after a Stop-event nudge / SessionStart:clear hook fires. Owns the promote / demote / cleanup / refactor / cascade / harvest / eval / patch-triage subcommands. Chunks self-describe via frontmatter (use_count, last_used, promote_when, demote_when, depends_on, status_history); mp:learn reads those keys and acts. New chunks always land at tier 0 (born-at-0 invariant). Patch-triage sweeps every ~/.melt/<skill>/patches/.failed/ marker and emits per-marker triage proposals (regenerate / hand-rewrite / delete / defer) for the LLM to resolve case-by-case.
user_invocable: true
disable-model-invocation: true
---

# mp:learn — lifecycle automation

`mp:learn` is the **policy engine** that watches chunks and patches over time and adjusts the gradient. The chunks themselves are self-describing — their frontmatter declares promote/demote conditions and a status history. `mp:learn`'s scripts read that metadata and act:

```sh
sh ~/.melt/learn/action help
# harvest [--transcript <path>] [--session <id>] [--apply]
# promote <chunk> [--dry-run]
# demote <chunk> [--dry-run]
# cleanup [--days N] [--yes]
# refactor [--yes]
# cascade <chunk>
# patch-triage [--format md|json]
# eval [--dry-run]
```

## Triggers

Three ways `mp:learn` fires:

1. **Automatic on session-end** — the Stop nudge hook (`melt-nudge.sh`) suggests `mp:learn harvest` before `/clear`. Agent reads live context and pipes proposals to `mp:learn harvest` on stdin.
2. **SessionStart:clear** — `melt-resume.sh` writes the prior `.jsonl` path to `~/.melt/learn/.pending-transcript`. Next `mp:learn harvest` consumes it (read-then-unlink) in transcript mode.
3. **Explicit gesture** — user invokes `mp:learn promote <chunk>` / `demote` / `cleanup` / `refactor` / `patch-triage` during a session, OR a scheduled sweep runs `mp:learn eval`.

## Chunk frontmatter schema (v1, Q-005)

Structured-key conditions (no DSL). All keys under `promote_when:` / `demote_when:` are ANDed. Unlisted keys are unconstrained.

```yaml
---
title: "Interactive rebase pre-flight checklist"
created: 2026-04-12
last_used: 2026-05-19
last_validated: 2026-05-01
use_count: 14
provenance:
  - session: 549fb61e-…
  - source: live-context
promote_when:
  use_count_min: 10
  days_since_last_use_max: 30
demote_when:
  days_since_last_use_min: 90
depends_on:
  - git-rebase/5-melting-pot/basic-rebase.md
status_history:
  - { tier: 0, at: 2026-04-12, reason: "born from session 549fb61e" }
  - { tier: 1, at: 2026-04-19, reason: "use_count crossed 3" }
  - { tier: 2, at: 2026-05-01, reason: "user validated against real conflict" }
---
```

### Recognized keys (under both `promote_when:` and `demote_when:`)

| Key | Type | Meaning |
|---|---|---|
| `use_count_min` | int | use_count ≥ value |
| `use_count_max` | int | use_count ≤ value |
| `days_since_last_use_min` | int | days since `last_used` ≥ value |
| `days_since_last_use_max` | int | days since `last_used` ≤ value |
| `days_since_validated_min` | int | days since `last_validated` ≥ value |
| `days_since_validated_max` | int | days since `last_validated` ≤ value |
| `tier_min` | 0..5 | current tier ≥ value |
| `tier_max` | 0..5 | current tier ≤ value |

The condition is "true" only when **every** listed key is satisfied. A `promote_when:` block with no recognized constraints evaluates to false (the author wrote it but didn't fill it in).

## Subcommands

### `harvest` — propose new/update/promote/demote actions

Two modes:

**Live-context mode.** The agent (current conversation) reads its own context, summarizes reusable techniques, and pipes a structured JSON proposal:

```sh
echo '{"proposals":[
  {"action":"create","skill":"git-rebase","chunk_name":"interactive-preflight","title":"…","body":"…","session":"abc123"},
  {"action":"promote","chunk":"git-rebase/0-melting-pot/scrap.md"},
  {"action":"demote","chunk":"git-rebase/5-melting-pot/stale.md"}
]}' | sh ~/.melt/learn/action harvest
```

Without `--apply`, the action validates the JSON and prints a per-proposal summary; the agent decides which to enact.
With `--apply`, the action executes `create` (write a new tier-0 chunk), `promote`, and `demote` actions. `update` is reported but not auto-applied (diffs need human review).

**Transcript mode.** After `/clear`, the SessionStart hook writes the prior `.jsonl` path to `~/.melt/learn/.pending-transcript`. The next `mp:learn harvest` reads + unlinks that file and prints the transcript path. The agent then reads the `.jsonl` itself and pipes structured proposals back in (loop = transcript mode + live-context mode chained).

Alternatively pass `--transcript <path>` explicitly.

### `promote <chunk>` / `demote <chunk>`

Evaluates `promote_when` / `demote_when` (see schema above) against the chunk's frontmatter. If satisfied:

- moves the chunk to `<tier+1>-melting-pot/` (promote) or `<tier-1>-melting-pot/` (demote);
- appends a `status_history` entry with reason "promoted from tier N" / "demoted from tier N".

If conditions are unmet, exits 1 with a warning. `--dry-run` shows what would happen without moving the file. **Q-009 v1: full tier mobility — no floor, no ceiling.** A chunk can move 0 ↔ 5 freely as signals change.

Chunk argument accepts:
- absolute path,
- `<skill>/<chunk-name>` (resolves via `mp_resolve_chunk_path`),
- `<skill>/<tier>-melting-pot/<name>.md`.

After a demote, `cascade <new-path>` runs to flag any dependents (see below).

### `cleanup [--days N] [--yes]`

Identifies stale chunks and proposes deletion. Stale = any of:
- chunk at tier 0 AND `days_since_last_use > N` (default `N=90`),
- chunk at tier 0 born more than N days ago and never used,
- chunk at tier 0 with missing `provenance` (no idea where it came from).

Without `--yes`, prints proposals only. With `--yes`, deletes them.

### `refactor [--yes]`

Identifies overlapping chunks (v1: normalized-title match across the entire pot). Prints proposals. v1 does NOT auto-consolidate — even with `--yes` the user is expected to merge by hand or via `mp:crud`.

### `cascade <chunk>`

Walks the `depends_on` graph: for each chunk in the pot that lists `<this-skill>/<this-chunk>` (or a path-style ref containing both basenames) in its `depends_on:`, emit a `FLAG ...` line. **Q-002 v1: flag-only — never auto-mutate.** Auto-cascade demotion is deferred; the user (or LLM in a later session) reviews flags and acts manually.

### `patch-triage [--format md|json]`

Sweeps `~/.melt/*/patches/.failed/*.patch.failed` markers. For each marker, parses the four envelope sections (patch / upstream excerpt / reject / timestamp) and emits a triage proposal with four choices:

- `regenerate` — the LLM (or user) rewrites the patch against current upstream.
- `hand-rewrite` — open the patch in `$EDITOR`.
- `delete` — `sh ~/.melt/crud/action patch-remove <skill> <patch-id>` (also clears the marker).
- `defer` — leave the marker; will re-surface next sweep.

Default output is markdown; `--format json` for programmatic consumers. Exit 0 if any proposals, 1 if no markers found.

**This is the LLM-mediated triage path from Q-001.** The patch apply pipeline itself is policy-free — it records markers and continues. `patch-triage` is where policy lives.

### `eval [--dry-run]`

Scheduled sweep: walks every chunk in the pot, runs `mp_eval_when promote_when` then `demote_when`, applies the move when conditions are met. Prints `eval: promoted=N demoted=M`. Suitable for a cron-like trigger (Phase 6 hooks).

With `--dry-run`, prints "DRY-RUN would promote/demote: <path>" without moving anything.

## Lifecycle invariants

- **Born at tier 0.** Every `harvest` create lands at `0-melting-pot/` regardless of how confident the agent is. Trust is earned.
- **Patches never touch upstream.** `mp:learn` only edits overlay state.
- **Status history is append-only.** Every promote/demote writes a new entry; no entries are ever removed.
- **Policy lives here, not in the apply pipeline.** Failed-patch markers are recorded by the indexer (`patch.sh`) and triaged by `mp:learn patch-triage` — never by the indexer itself.

## Path / config files (reference)

- `~/.melt/<skill>/N-melting-pot/<chunk>.md` — chunks (frontmatter + body).
- `~/.melt/learn/.pending-transcript` — SessionStart:clear handshake file (read-then-unlink).
- `~/.melt/<skill>/patches/.failed/<patch-id>.patch.failed` — failure markers (LLM-triaged).
- `~/.melt/learn/.tool-count-<session>` — nudge throttle marker (written by `melt-nudge.sh`).

## Edge cases

- **`promote_when:` block is empty.** No constraints → evaluates false. Chunk stays put. Author is expected to fill in constraints; an empty block is a no-op.
- **Chunk has no `last_used` or `created`.** `days_since_*` evaluates to 0 (today). Constraints like `days_since_last_use_min: 30` won't be satisfied — chunk stays put.
- **Promote target tier dir doesn't exist.** Created on demand. The chunk basename is preserved across moves.
- **Target chunk name collision in target tier.** Promote/demote refuse with "target exists" — user must rename or remove first.
- **`harvest` with no stdin and no `--transcript` and no `.pending-transcript`.** Exits 2 with usage hint.
- **`patch-triage` with no markers.** Prints "no failed patches to triage." and exits 1.

## Related

- `mp:crud patch-add`, `patch-remove` — write patches; `patch-triage` proposes the remove call.
- `mp:search` — runs the FTS5 index over patched+overlay content.
- `mp:load` — reads chunks and patches; respects the same tier structure mp:learn moves them through.
- `~/.melt/lib/tier.sh:mp_append_status_history` — the helper this skill calls on every move.
- `install/hooks/melt-nudge.sh`, `melt-resume.sh` — harness-agnostic hooks that trigger `mp:learn harvest`.
- `plans/open_questions.md` — Q-002 (cascade), Q-005 (grammar), Q-006 (harvest provenance), Q-009 (tier mobility) all baked-in as v1 defaults here.
