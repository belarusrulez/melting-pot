---
name: mp-learn
description: Lifecycle automation for melting-pot chunks and patches. Use when the user says "harvest reusable techniques", "what should I save from this session", "promote this chunk", "demote that chunk", "refactor overlapping chunks", "triage failed patches", or after a Stop-event nudge / SessionStart:clear hook fires. Owns the promote / demote / refactor / cascade / harvest / patch-triage subcommands. Tier movement is driven purely by usage quality: a good use promotes (+1 tier), a bad use demotes (-1 tier), and a bad use at tier 0 removes the chunk — no time-decay, no promote_when/demote_when rules. New chunks always land at tier 0 (born-at-0 invariant). Patch-triage sweeps every ~/.melt/<skill>/patches/.failed/ marker and emits per-marker triage proposals (regenerate / hand-rewrite / delete / defer) for the LLM to resolve case-by-case.
user_invocable: true
disable-model-invocation: true
---

# mp-learn — lifecycle automation

`mp-learn` adjusts the gradient based on **usage quality**. There are no rules and no time-decay: the caller reports whether a use was good or bad, and the chunk moves one tier accordingly.

```sh
sh ~/.melt/learn/action help
# harvest [--transcript <path>] [--session <id>] [--apply]
# promote <chunk> [--dry-run]    good use: +1 tier (refuse at tier 5)
# demote <chunk> [--dry-run]     bad use: -1 tier; at tier 0, remove the chunk
# refactor [--yes]
# cascade <chunk>
# patch-triage [--format md|json]
```

## The promotion model — good/bad usage only

Tier movement is driven by one signal: did the skill help or not?

- **Good use → `promote`** — the chunk moves up one tier (`+1`). At tier 5 (pure alloy) it has nowhere higher to go, so promote refuses with exit 1.
- **Bad use → `demote`** — the chunk moves down one tier (`-1`). At tier 0 (scrap) it has nowhere lower to go, so demote **removes the chunk** from the pot.

There are no `promote_when` / `demote_when` rules, no `use_count`/`days`-based thresholds, and no scheduled sweep. The caller decides "good" vs "bad" and calls `promote` or `demote`. `use_count` / `last_used` remain in frontmatter as informational metadata only — they no longer gate movement.

### Reporting use — close the loop (don't let chunks rot at tier 0)

The gradient only climbs if someone reports good use. Harvest alone never promotes — it just births chunks at tier 0. **Make use-reporting a reflex, not a special gesture:** when you act on a skill and one of its **overlay chunks** (anything under `<skill>/N-melting-pot/`) materially helped, call `mp-learn promote <chunk>` right then; if a chunk actively misled you, `mp-learn demote <chunk>`. One signal per real use.

- This belongs at the **end of a task**, in the main agent's compile/wrap-up step — after you've seen whether the chunk earned its keep.
- **Only overlay chunks move.** A pure registered `SKILL.md` with no overlay chunks has nothing in the gradient (expected — "good use → promote" has no target until a chunk exists). Don't fabricate a chunk just to promote it; harvest one only if there's genuinely new, reusable knowledge.
- **One use = one tier step.** Don't jump a chunk several tiers for a single good session — recurrence across sessions is the whole point of the climb.

## Triggers

Four ways `mp-learn` fires:

1. **Automatic on session-end** — the Stop nudge hook (`melt-nudge.sh`) suggests `mp-learn harvest` before `/clear`. Agent reads live context and pipes proposals to `mp-learn harvest` on stdin.
2. **SessionStart:clear** — `melt-resume.sh` writes the prior `.jsonl` path to `~/.melt/learn/.pending-transcript`. Next `mp-learn harvest` consumes it (read-then-unlink) in transcript mode.
3. **Use-reporting reflex** — whenever an overlay chunk helps or misleads during a task, `promote`/`demote` it on the spot (see *Reporting use* above). This is the signal that actually drives the gradient.
4. **Explicit gesture** — user invokes `mp-learn promote <chunk>` / `demote` / `refactor` / `patch-triage` during a session.

## Chunk frontmatter schema (v1)

Chunks carry identity + provenance + an append-only status history. They no longer carry promote/demote rule blocks.

```yaml
---
title: "Interactive rebase pre-flight checklist"
created: 2026-04-12
last_used: 2026-05-19
use_count: 14
provenance:
  - session: 549fb61e-…
  - source: live-context
depends_on:
  - git-rebase/5-melting-pot/basic-rebase.md
status_history:
  - { tier: 0, at: 2026-04-12, reason: "born from session 549fb61e" }
  - { tier: 1, at: 2026-04-19, reason: "promoted from tier 0" }
  - { tier: 2, at: 2026-05-01, reason: "promoted from tier 1" }
---
```

| Field | Meaning |
|---|---|
| `title` | human-readable label |
| `created` | birth date (YYYY-MM-DD) |
| `last_used` / `use_count` | informational only — do NOT gate tier movement |
| `provenance` | where the chunk came from (session / source) |
| `depends_on` | other chunks this one relies on (drives `cascade` flags) |
| `status_history` | append-only log of every tier move |

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

**Transcript mode.** After `/clear`, the SessionStart hook writes the prior `.jsonl` path to `~/.melt/learn/.pending-transcript`. The next `mp-learn harvest` reads + unlinks that file and prints the transcript path. The agent then reads the `.jsonl` itself and pipes structured proposals back in (loop = transcript mode + live-context mode chained).

Alternatively pass `--transcript <path>` explicitly.

#### Harvesting well — generalize, don't memorize

A harvested chunk is reusable knowledge, not a session diary. The common failure is baking in the session's concrete identifiers (`sync-west1-tmux`, `SYNCC17`, a specific repo path) so the chunk only ever fires for that one situation and pollutes search for everyone else. When you author a `create` proposal:

- **State the pattern, not the instance.** Write the rule in general terms ("resolve the region from the active flow's `--profile=`; prefer the dedicated single-id block over shared groups").
- **Keep exactly one concrete example** as illustration, and label it as such. Strip the rest.
- **Check for a duplicate first.** Before proposing `create`, `mp-search` the body — if it converges on an existing chunk, propose an `update`/patch to that chunk instead of a parallel one. (On `--apply`, the action also runs an advisory same-skill near-duplicate check and warns; it never blocks.)
- **Title it by capability**, not by the session ("region resolution from active tmux flow", not "fix for today's test run").

#### Acting on a harvest result

When `harvest` reports what it created (e.g. one new tier-0 chunk), the cheap right move — the born-at-0 invariant already hedged the risk:

1. **Generalization check** (~30s) — does it leak session-specific IDs? If so, edit it down to pattern + one example. This is the highest-value review.
2. **Truth check** — is the refinement actually correct and reusable, or a one-session coincidence? If unsure, that uncertainty *is* the tier-0 signal — leave it low.
3. **Leave it at tier 0.** Don't promote on first sighting; promotion is earned by recurrence (see *Reporting use*).
4. **Prune lazily, in batches.** A bad tier-0 chunk costs only slight index noise and is one `demote`/`mp-crud trash` away. Sweep tier-0 chunks periodically rather than gating every harvest.

### `promote <chunk>` / `demote <chunk>`

The caller reports a use as good (`promote`) or bad (`demote`):

- **`promote`** moves the chunk to `<tier+1>-melting-pot/` and appends a `status_history` entry "promoted from tier N". At tier 5 it refuses (exit 1) — nowhere higher.
- **`demote`** moves the chunk to `<tier-1>-melting-pot/` and appends "demoted from tier N". **At tier 0 it removes the chunk** (flagging dependents via `cascade` first) — nowhere lower.

`--dry-run` shows what would happen (including "would REMOVE" at tier 0) without touching the filesystem. **Full tier mobility — a chunk can travel 0 ↔ 5 freely** as good/bad signals accumulate.

Chunk argument accepts:
- absolute path,
- `<skill>/<chunk-name>` (resolves via `mp_resolve_chunk_path`),
- `<skill>/<tier>-melting-pot/<name>.md`.

After a demote (move or tier-0 removal), `cascade` runs to flag any dependents (see below).

### `refactor [--yes]`

Identifies overlapping chunks (v1: normalized-title match across the entire pot). Prints proposals. v1 does NOT auto-consolidate — even with `--yes` the user is expected to merge by hand or via `mp-crud`.

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

## Lifecycle invariants

- **Born at tier 0.** Every `harvest` create lands at `0-melting-pot/` regardless of how confident the agent is. Trust is earned.
- **Movement is usage-driven.** Good use promotes, bad use demotes, bad use at tier 0 removes. No rules, no time-decay.
- **Patches never touch upstream.** `mp-learn` only edits overlay state.
- **Status history is append-only.** Every promote/demote writes a new entry; no entries are ever removed.
- **Policy lives here, not in the apply pipeline.** Failed-patch markers are recorded by the indexer (`patch.sh`) and triaged by `mp-learn patch-triage` — never by the indexer itself.

## Path / config files (reference)

- `~/.melt/<skill>/N-melting-pot/<chunk>.md` — chunks (frontmatter + body).
- `~/.melt/learn/.pending-transcript` — SessionStart:clear handshake file (read-then-unlink).
- `~/.melt/<skill>/patches/.failed/<patch-id>.patch.failed` — failure markers (LLM-triaged).
- `~/.melt/learn/.tool-count-<session>` — nudge throttle marker (written by `melt-nudge.sh`).

## Edge cases

- **`promote` at tier 5.** Refuses with exit 1 — already at the ceiling (pure alloy).
- **`demote` at tier 0.** Removes the chunk (after flagging dependents). `--dry-run` reports "would REMOVE" and keeps the file.
- **Promote/demote target tier dir doesn't exist.** Created on demand. The chunk basename is preserved across moves.
- **Target chunk name collision in target tier.** Promote/demote refuse with "target exists" — user must rename or remove first.
- **`harvest` with no stdin and no `--transcript` and no `.pending-transcript`.** Exits 2 with usage hint.
- **`patch-triage` with no markers.** Prints "no failed patches to triage." and exits 1.

## Related

- `mp-crud patch-add`, `patch-remove` — write patches; `patch-triage` proposes the remove call.
- `mp-search` — runs the FTS5 index over patched+overlay content.
- `mp-load` — reads chunks and patches; respects the same tier structure mp-learn moves them through.
- `~/.melt/lib/tier.sh:mp_append_status_history` — the helper this skill calls on every move.
- `install/hooks/melt-nudge.sh`, `melt-resume.sh` — harness-agnostic hooks that trigger `mp-learn harvest`.
- `plans/open_questions.md` — Q-002 (cascade), Q-006 (harvest provenance) baked-in as v1 defaults here. Q-005 (promote grammar) resolved: usage-driven good/bad, no rule schema.
