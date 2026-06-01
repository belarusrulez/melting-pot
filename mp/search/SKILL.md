---
name: mp-search
description: Three-axis search across every skill in the melting pot — both registered upstream skills AND your overlay (~/.melt/<skill>/) content, with your git-patches applied in-memory at index time. Use when the user asks "do I have a skill for X", "find a skill that …", "is there a skill to …", "search the pot", or any "find/locate a skill" phrasing. Pass THREE positional queries (literal phrase, synonym/jargon, intent/goal); results are fused via Reciprocal Rank Fusion (RRF, k=10) and skills matching 2+ axes surface in a "Convergence" section — the strongest signal.
user_invocable: true
---

# mp-search — multi-axis skill search

Skill sources are discovered from two places:

1. **Registered** — every directory listed in `~/.melt/repos.patterns` (one `<abs-root><TAB><pattern>` per line). Holds canonical upstream content the user did not author.
2. **Overlay** — `~/.melt/<skill>/` directories the user owns. Holds user-grown chunks (under `0-melting-pot/`..`5-melting-pot/`), git-patches against upstream (under `patches/`), and any `meta.md` / `SKILL.md` manifests.

The action discovers every skill (union of layers), maintains a SQLite FTS5 index at `~/.melt/search/index.db`, applies your `patches/*.patch` files in-memory against upstream content at index time, and answers multi-axis queries.

## CRITICAL — pass THREE queries

When invoking `mp-search`, **always pass three positional query strings**, each capturing a different axis of what the user is asking for:

1. **literal** — words/phrases the user actually used (or might have used)
2. **synonym / jargon** — domain-specific terms for the same concept
3. **intent / goal** — what the user is trying to *accomplish*, phrased differently

The script merges the three rankings via **Reciprocal Rank Fusion (RRF, k=10)** with each per-query result capped at top-5 before fusion. Skills that match 2+ axes are grouped in a **Convergence** section — that's the strongest signal and where the right answer almost always lives. Skills matching only one axis appear under **Single-axis hits**.

If you call the action with fewer than 3 queries, you'll get a `WARN:` on stderr and weaker results. Don't do that.

### Why three axes

The caller (you) doesn't know exactly what vocabulary the skill author used. Three rephrasings hedge against vocabulary mismatch — and convergence across axes is a much stronger ranking signal than any single bm25 score, since bm25 magnitudes don't compare cleanly across different queries.

## How to invoke

```sh
# 3-axis search (the common case):
sh ~/.melt/search/action search "<axis-1: literal>" "<axis-2: synonym>" "<axis-3: intent>"

# Shorthand — bare positional args route to `search`:
sh ~/.melt/search/action "<axis-1>" "<axis-2>" "<axis-3>"

# Options (place flags BEFORE the query strings):
sh ~/.melt/search/action search --limit 30 --format json "<q1>" "<q2>" "<q3>"

# Maintenance:
sh ~/.melt/search/action reindex          # rebuild FTS5 index (atomic)
sh ~/.melt/search/action list-roots       # print resolved roots from repos.patterns
sh ~/.melt/search/action doctor           # validate config
sh ~/.melt/search/action doctor --write-sample   # seed a starter ~/.melt/repos.patterns
```

`--format`: `text` (default — two sections: Convergence + Single-axis, with metadata + `→ <full path>` line under each hit), `tsv` (one row per hit: `path<TAB>name<TAB>dirname<TAB>description<TAB>score<TAB>axes<TAB>origin<TAB>avg_tier<TAB>hits<TAB>patches_applied<TAB>patches_failed`), or `json`.

`--limit`: cap on returned rows (default 20).

## What each row tells you

Per-skill metadata surfaced on every hit:

- **origin**: `reg` (only registered upstream contributes), `ovl` (only overlay contributes — overlay-born skill), or `mix` (both layers contribute — overlay holds patches and/or overlay-authored chunks alongside upstream content).
- **avg_tier**: weighted-average tier across all chunks (1 decimal). `5.0` = all content is tier-5 canonical; `2.0` = mostly mid-tier.
- **hits**: chunk distribution as `[tier:count, …]`. E.g., `[5:2, 3:1, 0:1]` = two tier-5 chunks, one tier-3, one tier-0.
- **patches=N applied [failed=M]**: shown only when patches exist. Failed patches were recorded as `~/.melt/<skill>/patches/.failed/<patch-id>.failed` markers — resolve via `mp-learn patch-triage`.

## How skills are used (CRITICAL)

**Skills are NOT registered with the agent harness** — `mp-search` returns a *path*, you read the `SKILL.md` (or `meta.md`) at that path.

The workflow:

1. Run `mp-search` with 3 queries.
2. Pick the top hit from Convergence (or the top Single-axis if Convergence is empty).
3. **Read the manifest at the full path shown after `→`** (`<path>/meta.md` if it exists, otherwise `<path>/SKILL.md`) and **immediately start following its instructions**. If you need the full skill content with all chunks and patches applied, use `mp-load <skill-name>` — that composes manifest + every chunk across every tier + applied patches into one document.
4. If, after reading, that skill is clearly not the right fit, fall back to the next-ranked hit and repeat — **up to 3 candidates total**. Only if all 3 are wrong, tell the user and ask how to proceed.

There is no slash-command activation, no `/<skill-name>` invocation. The path IS the skill.

### Do NOT ask before using the top hit

Once `mp-search` returns a top hit, **do not ask the user for permission to read it or run it**. Reading the manifest and executing its instructions IS the job — asking first is friction. The only reasons to pause:

- All 3 top candidates have been read and none fit → tell the user, ask what to do.
- The skill's own instructions require confirmation for a destructive/irreversible step (commits, pushes, deletes, etc.) — follow the skill's own guidance, not a generic "should I start?" prompt.

Phrase status updates as actions ("Reading `git:rebase` and applying it now."), not as offers ("Want me to…?").

## Example

User asks: "do I have a skill for interactive git rebase?"

```sh
sh ~/.melt/search/action "interactive rebase" "git history rewrite squash fixup" "edit past commits"
```

Output:

```
## Convergence (matched 2+ axes — strongest signal)
  git:rebase             axes=3 score=0.2727 origin=mix avg_tier=3.5 hits=[5:2, 3:1, 0:1]  rewrite git history, interactively or non-interactively
           patches=2 applied
           → /Users/me/Projects/some-team-repo/git-rebase
```

Then: `mp-load git:rebase` (or read `meta.md` / `SKILL.md` at the path) and follow its instructions.

## Auto-reindex

A reindex runs automatically on every action invocation when the indexed content drifts. The drift hash covers:

- every manifest (`meta.md` or `SKILL.md`)
- every chunk under `0-melting-pot/`..`5-melting-pot/` (with `-L` so symlinked upstream tier dirs are walked)
- every `patches/*.patch`
- every `patches/.failed/*.failed` marker
- every `N-melting-pot/` symlink target (so a re-pointed symlink triggers reindex)

Manual `reindex` is only needed to force a rebuild (e.g., schema changes).

## Exit codes

| code | meaning                                              |
|------|------------------------------------------------------|
| 0    | hits returned                                        |
| 1    | no skills matched                                    |
| 2    | config error (missing/invalid `~/.melt/repos.patterns`) |
| 3    | index error (sqlite/FTS5 failure)                    |

## When you can't find anything

- Try broader / more synonymous queries — the user may have phrased the intent very differently from the skill description.
- Run `sh ~/.melt/search/action list-roots` to confirm the expected repo is registered.
- If still nothing, say so explicitly and offer to either (a) add the missing repo to `~/.melt/repos.patterns` or (b) create a new skill via `mp-crud`.
- DO NOT try `/<skill-name>` slash-commands; they aren't registered. Always go through `mp-search` → path → read manifest (or `mp-load`).

## Related

- `mp-load <skill-name>` — compose the full skill content (manifest + every chunk + applied patches) as one document. Use this after `mp-search` to get the actual skill body.
- `mp-list` — flat inventory of every skill the pot can see.
- `mp-crud` — scaffold, validate, trash, restore skills; manage patches against third-party skills.
- `mp-learn` — lifecycle ops (promote/demote/cleanup/refactor/patch-triage).
- `~/.melt/repos.patterns` — user-edited list of registered roots (melting-pot reads ONLY this path).
