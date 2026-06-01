---
name: mp-list
description: Flat inventory of every skill the pot can see — union of registered (~/.melt/repos.patterns) + overlay (~/.melt/<skill>/). Use when the user asks "list my skills", "what skills do I have", "show all skills", "enumerate skills", "skill inventory", "what's in the pot", or wants a flat catalog rather than ranked search. One row per skill with origin (reg/ovl/mix), tiers_present (e.g. [0,2,5]-melting-pot or legacy), chunk_count, patches_count, patches_failed_count, description, full path. Unlike mp-search (which ranks by query relevance), mp-list returns the whole set — optionally filtered by registered root or skill-name pattern.
user_invocable: true
---

# mp-list — enumerate every skill in the pot

melting-pot has two layers: registered upstream content (listed in `~/.melt/repos.patterns`) and the user overlay (`~/.melt/<skill>/`). `mp-list` walks both, unions by skill basename, and prints one row per skill with the tier/patch metadata the search ranker also uses.

Use `mp-search` when you want ranked relevance for a specific intent. Use `mp-list` when you want the full catalog or a filtered subset.

## How to invoke

```sh
sh ~/.melt/list/action                              # list every skill, text format
sh ~/.melt/list/action --format tsv                 # one row per skill, tab-separated
sh ~/.melt/list/action --format json                # JSON array
sh ~/.melt/list/action --root <abs-root>            # restrict to one registered root (repeatable)
sh ~/.melt/list/action --name '<glob>'              # filter by skill DIRNAME glob (e.g. 'git-*')
sh ~/.melt/list/action --name 're:<regex>'          # POSIX ERE over dirname
sh ~/.melt/list/action --names-only                 # emit just the frontmatter `name:` per line
sh ~/.melt/list/action --count                      # print total count and exit
```

`--match` is accepted as a synonym for `--name`.

Flags compose: `sh ~/.melt/list/action --root /Users/me/Projects/my-skills --name 'git-*' --format tsv`.

## Output formats

- **text** (default) — aligned grouping by origin → root:

  ```
  [reg] /Users/me/Projects/melting-pot/mp (3 skills)
    mp-search              Three-axis search across patched+overlay content
      tiers=legacy chunks=1 patches=0 failed=0
      → /Users/me/Projects/melting-pot/mp/search
    …

  [ovl] /Users/me/.melt (2 skills)
    git:rebase             rewrite git history, interactively
      tiers=[0,3,5]-melting-pot chunks=4 patches=2 failed=0
      → /Users/me/.melt/git-rebase
    …

  [mix] /Users/me/.melt (1 skill)
    some:upstream          legacy upstream skill with overlay patches
      tiers=legacy chunks=1 patches=1 failed=1
      → /Users/me/.melt/some-upstream

  total: 6 skill(s) across 3 group(s)
  ```

- **tsv** — one row per skill: `name<TAB>dirname<TAB>origin<TAB>tiers_present<TAB>chunk_count<TAB>patches_count<TAB>patches_failed_count<TAB>description<TAB>path<TAB>root`. Stable column order; safe for `awk`, `cut`.

- **json** — `{"results":[{"name":..., "dirname":..., "origin":..., "tiers_present":..., "chunk_count":N, "patches_count":N, "patches_failed_count":N, "description":..., "path":..., "root":...}, ...], "count": N}`. Hand-rolled (no jq).

## Origin tags

| tag | meaning |
|-----|---------|
| `reg` | only registered upstream contributes (canonical content, no overlay patches or chunks) |
| `ovl` | only overlay contributes (mp-learn-born or hand-scaffolded under ~/.melt/) |
| `mix` | both layers contribute — overlay carries patches and/or overlay-authored chunks |

## tiers_present rendering

- `[0,2,5]-melting-pot` — native six-tier layout with chunks at tier 0, 2, and 5.
- `legacy` — SKILL.md-only (no `N-melting-pot/` directories anywhere).

## Exit codes

| code | meaning                                                |
|------|--------------------------------------------------------|
| 0    | listed at least one skill                              |
| 1    | no skills discovered (config valid but empty)          |
| 2    | config error (bad flag, unknown format)                |

## When NOT to use mp-list

- The user is looking for a skill that *does X* — use `mp-search` (ranked, multi-axis).
- The user wants to create/edit/delete a skill — use `mp-crud`.
- The user wants to read a specific skill's full content — use `mp-load`.

## Related

- `mp-search` — ranked multi-axis search across the same corpus.
- `mp-crud` — create / update / delete / import skills + patches.
- `mp-load` — compose a single skill's full content (manifest + chunks + patches).
- `~/.melt/repos.patterns` — the source list mp-list walks (registered layer).
- `~/.melt/lib/discover.sh`, `tier.sh`, `patch.sh` — shared helpers.
