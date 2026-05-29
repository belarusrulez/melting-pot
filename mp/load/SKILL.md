---
name: mp:load
description: Compose and return a skill's FULL content — manifest + every chunk across every tier + applied git-patches — as one unified document. Use after mp:search picks a candidate and you want the actual skill body (not just the digest row). Output is markdown by default; JSON for programmatic consumers. Flags let you restrict to specific tiers, skip patches (raw upstream view), or include each chunk's status_history.
user_invocable: true
---

# mp:load — fully-composed skill document

`mp:search` returns a digest (one row per skill with ranking metadata). `mp:load` returns the **actual content** — manifest, every chunk across every `N-melting-pot/` tier dir, and your overlay patches applied in-memory against upstream content — as one document.

## How to invoke

```sh
sh ~/.melt/load/action <skill-name>

# Flags:
sh ~/.melt/load/action git:rebase --format json
sh ~/.melt/load/action git:rebase --tiers 5,3       # only pure-alloy + mixed-in
sh ~/.melt/load/action git:rebase --no-patches      # raw upstream (no overlay patches)
sh ~/.melt/load/action git:rebase --with-history    # include status_history entries
```

`<skill-name>` matches either the manifest's frontmatter `name:` field (e.g. `git:rebase`) or the directory basename (e.g. `git-rebase`). Resolution prefers `name:` matches but falls back to basename.

## Output shape (markdown, default)

```markdown
# git:rebase

> rewrite git history, interactively or non-interactively

origin=mix | tiers present: [0,3,5] | patches applied: 2 | patches failed: 0

## Tier 5 — Pure alloy

### SKILL.md (patches applied: 2, failed: 0)
<patched upstream body>

### basic-rebase.md — basic rebase walkthrough
<body>

## Tier 3 — Mixed-in

### autosquash-tips.md — autosquash tips
<body>

## Tier 0 — Scrap

### ai-driven-split.md — AI-driven split
<body>
```

Tier order: **5 → 0** (most-refined first). Within a tier, chunks sort alphabetically by basename. If the skill has a legacy `SKILL.md` manifest, it renders at tier 5 alongside any `5-melting-pot/*.md` files (neither shadows the other).

## Flags

| Flag | Effect |
| --- | --- |
| `--format md` (default) | Markdown output. |
| `--format json` | One JSON object: `{name, basename, description, origin, tiers_present, patches_applied, patches_failed, tiers: [{tier, chunks: [{name, title, body, history?}]}]}`. |
| `--tiers 5,3` | Restrict to listed tiers (comma-separated). Tiers not listed are dropped from the output. |
| `--no-patches` | Skip in-memory patch apply — show the raw upstream content. Useful for diffing what your patches change. |
| `--with-history` | After each chunk body, surface its `status_history:` block; in markdown a trailing **`## Status history (across all chunks)`** section sorts entries by date descending. |

## How `mp:load` resolves a skill

1. Walk discovery (`mp_discover_skills`) — union of registered upstream + overlay layers.
2. For each discovered skill, look at:
   - Frontmatter `name:` of `meta.md` (or `SKILL.md` if no `meta.md`) — does it equal `<skill-name>`?
   - Directory basename — does it equal `<skill-name>`?
3. First match wins. If neither hits, exit 1 with `no such skill: <skill-name>`.

## Patch application semantics

When the manifest is a legacy `SKILL.md` (upstream content) and the overlay carries `patches/*.patch` files, those patches are applied in numeric order in-memory at compose time. The composed output shows the patched content; the upstream file is never touched.

- **Patch success** → patched lines appear in the output; the header reads `patches applied: N`.
- **Patch failure** → a marker is written to `~/.melt/<skill>/patches/.failed/<patch-id>.failed` (Q-001) and apply continues with the next patch. The composed output reads `patches failed: M`. Resolve failures via `mp:learn patch-triage`.
- **`--no-patches`** → no patches are applied, no `.failed/` markers are written. Pure upstream view.

## Exit codes

| code | meaning |
| --- | --- |
| 0 | document composed and emitted |
| 1 | no such skill (`<skill-name>` matched neither `name:` nor basename) |
| 2 | flag / usage error |

## When to use mp:load vs read the manifest directly

- **Read the manifest directly** (`<path>/meta.md` or `<path>/SKILL.md`) when you only need the skill's procedure / instructions — the manifest is usually self-contained for legacy skills, and for native six-tier skills `meta.md` carries the procedural document.
- **Use `mp:load`** when you also need the chunk content (e.g., examples, scrap notes, refined snippets across multiple tiers) AND you want patches already applied. That's the "give me everything" mode.

## Related

- `mp:search` — three-axis search; returns paths to feed into `mp:load`.
- `mp:list` — flat inventory; no content, just metadata.
- `mp:crud` — scaffold, validate, manage patches.
- `mp:learn patch-triage` — resolve `.failed/` patch markers.
