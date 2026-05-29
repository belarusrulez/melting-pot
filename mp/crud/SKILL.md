---
name: mp:crud
description: Lifecycle ops on melting-pot skills and patches. Use when the user says "make a new skill", "add a skill for X", "scaffold a skill", "update the X skill", "remove this skill", "import these skills", "register this folder", "add a patch against upstream X", "list patches", "remove a stale patch", "validate the X skill", "soft-delete the X skill", or describes a workflow they want captured. Native scaffold builds the six-tier layout under ~/.melt/<name>/ with 0-melting-pot/ seeded; --legacy writes a flat SKILL.md. Patch subcommands manage ~/.melt/<skill>/patches/*.patch — the non-destructive way to edit third-party upstream content. Soft-delete via mv to ~/.melt/.trash/; name-derivation rule first '-' becomes ':' (e.g. my-cool-tool → my:cool-tool). All mutating subcommands accept --dry-run.
user_invocable: true
disable-model-invocation: true
---

# mp:crud — lifecycle for skills + patches

`mp:crud` is a **mixed procedure**:

- You (the agent) own the *judgment* steps — update-vs-create, choose target repo, write description prose, recognize when a candidate from `mp:search` is the right update target.
- The deterministic filesystem operations are delegated to `sh ~/.melt/crud/action <subcommand>`, so the result is identical every time and costs zero LLM tokens.

```sh
sh ~/.melt/crud/action help
# collision-check <dirname>             — exit 0=ok, 1=collision
# scaffold <name> [--legacy|--native]   — default native six-tier under ~/.melt/<name>/
# validate <skill-name|dir>             — check structure + patches + .failed markers
# trash <skill-name|dir>                — soft-delete to ~/.melt/.trash/
# restore <trash-entry>                 — mv back to orig_path from meta
# import-preview <root>                 — TSV: path  name  desc  tiers  issues
# patch-add <skill> <patch-file>        — copy patch in, renumber to next NNN slot
# patch-list <skill>                    — patch-id  status (applies/failed/not-yet-attempted)
# patch-remove <skill> <patch-id>       — also clears matching .failed marker
# patch-validate <skill>                — dry-run apply all patches (read-only)
```

All mutating subcommands accept `--dry-run`.

## Integrity rule — ALWAYS validate after create / update / patch-* mutation

After every Step 4 (Update), Step 5 (Create), Step 7 (Import), or any `patch-add` / `patch-remove`, run:

```sh
sh ~/.melt/crud/action validate <skill-name>
```

It checks: manifest (meta.md or SKILL.md) exists with frontmatter + non-empty `name`/`description`; tier dirs use the `N-melting-pot/` suffix (bare `N/` → warning per Q-007); every chunk has frontmatter; every `patches/*.patch` parses; every `.failed/` marker has the expected envelope shape; flags stale markers (patch removed but marker still present). If validate exits non-zero, fix issues **before** confirming success to the user.

## Triggers

User says any of: "make a new skill", "add a skill for X", "create a skill that …", "update the X skill", "edit the Y skill", "fix Z in the Z skill", "remove the X skill", "delete X skill", "import these skills", "register this folder", "add this skills repo", "patch the upstream X", "add a patch against X", "list patches for X", "remove a stale patch", or describes a workflow they want captured.

## Two scaffold modes

### Native (default) — overlay six-tier

```sh
sh ~/.melt/crud/action scaffold my-new-pattern
```

Writes:
```
~/.melt/my-new-pattern/
├── meta.md                   # frontmatter (name + description)
└── 0-melting-pot/
    └── first.md              # tier-0 chunk born here per the "born at 0" invariant
```

Use this for everything you create — mp:learn-born skills land here too. The chunk frontmatter includes `promote_when`, `demote_when`, `status_history`, and `provenance` per the chunk schema.

### Legacy — flat SKILL.md

```sh
sh ~/.melt/crud/action scaffold third-party-target --legacy --target-dir /some/upstream/repo/third-party-target
```

Writes only `<target>/SKILL.md`. Use this when shipping a skill into a registry that expects the old format. `--target-dir` lets you write outside `~/.melt/`.

## Procedure

### Step 1 — Did the user name a specific skill?

A user message **names a skill** if it contains an explicit reference: a frontmatter name (`git:rebase`), a dirname (`git-rebase`), or "the X skill" where X is a known existing skill.

- **Yes, named** → Step 4 (Update). No candidate search.
- **No** → Step 2.

### Step 2 — Search for candidates that might already cover the intent

Distil the request into 3 axis queries (literal / synonym / intent) — same shape as `mp:search`. Run:

```sh
sh ~/.melt/search/action "<literal>" "<synonym>" "<intent>" --limit 8
```

Look at the **Convergence** section. Skills with `axes=3` (or `axes=2` with a high score) are candidates worth proposing as updates instead of duplicating.

If Convergence is empty and no Single-axis hit scores above ~0.10, skip to Step 5. Otherwise Step 3.

### Step 3 — Present candidates (or skip to create)

```
I found existing skills that look related:

  1. <name> — <description> (at <path>)
  2. ...

Update one of these, or create a new skill?
```

If the user picks N → Step 4. If they say "new" / "none of these" → Step 5.

### Step 4 — Update an existing skill

1. Read the manifest (`meta.md` or `SKILL.md`).
2. Apply targeted edits with `Edit`. Preserve the existing `name:` exactly — never rename via update; the user must rename the directory if they want a different `name:`.
3. If touching `description:`, front-load with trigger phrases.
4. **Validate** (mandatory):
   ```sh
   sh ~/.melt/crud/action validate <skill-name>
   ```
5. Reindex: `sh ~/.melt/search/action reindex --full`.
6. Confirm: "Updated `<name>`."

### Step 5 — Create a new skill

1. Pick a dirname (kebab-case, namespace-prefixed: `git-bisect`, `aws-s3-sync`). The first `-` becomes `:` in the `name:` field.
2. Collision check:
   ```sh
   sh ~/.melt/crud/action collision-check <dirname>
   ```
3. Scaffold (native by default):
   ```sh
   sh ~/.melt/crud/action scaffold <dirname>
   ```
   Edit the TODOs in `meta.md` (description, body) and `0-melting-pot/first.md`.
4. Validate (mandatory).
5. Reindex.
6. Confirm: "Created `<name>` at `~/.melt/<dirname>/`."

### Step 6 — Delete a skill

Soft-delete by default:

```sh
sh ~/.melt/crud/action trash <skill-name>
```

Prints the trash path. Restore later with:

```sh
sh ~/.melt/crud/action restore <trash-path>
```

Hard-delete (only when user says "purge" / "permanently delete"):

```sh
rm -rf ~/.melt/<skill-name>
```

Reindex after either path.

### Step 7 — Import / register existing skills

```sh
sh ~/.melt/crud/action import-preview <root>
```

Emits TSV: `path<TAB>name<TAB>description<TAB>tiers<TAB>issues`. The `tiers` column shows the layout: `[0,2,5]-melting-pot` for native, `legacy` for SKILL.md-only. The `issues` column flags `missing-name`, `missing-description`, `no-frontmatter`, or `bare-tier-dir-N` (Q-007 violations).

To make discoverable, append the root to `~/.melt/repos.patterns`:

```
<abs-root>	*
```

Then `sh ~/.melt/search/action reindex --full`.

### Step 8 — Patch a third-party (upstream) skill

When you DON'T own the upstream repo but need to fix a typo, remove an outdated section, or add a context-specific example, write a git patch and register it under the overlay.

1. Produce the patch (`git diff > my-fix.patch` or hand-author).
2. Add it:
   ```sh
   sh ~/.melt/crud/action patch-add <skill> <patch-file>
   ```
   Numbered to the next `NNN-…` slot. Returns the destination path.
3. Validate (read-only — does NOT write `.failed/` markers):
   ```sh
   sh ~/.melt/crud/action patch-validate <skill>
   ```
   Reports `applies` / `failed` per patch.
4. If a patch shows `failed`, either fix it in place OR remove and re-author:
   ```sh
   sh ~/.melt/crud/action patch-remove <skill> <patch-id>
   ```
   `patch-remove` also clears any matching `.failed/` marker.
5. Reindex.

Note: failures during normal `mp:search` indexing record `.failed/` markers automatically and continue past the failure (Q-001 policy-free apply). Use `mp:learn patch-triage` later to resolve them case-by-case.

## Name derivation (canonical)

The `name:` is the directory basename with **only the first `-` replaced by `:`**.

| dirname            | derived `name:`                |
|--------------------|--------------------------------|
| `my-skill`         | `my:skill`                     |
| `my-cool-tool`     | `my:cool-tool`                 |
| `git-rebase`       | `git:rebase`                   |
| `alpha-beta-gamma` | `alpha:beta-gamma`             |
| `noskill`          | `noskill` (no dash → unchanged)|

## Path / config files (reference)

- `~/.melt/repos.patterns` — `<abs-root><TAB><pattern>` per line. The SOLE config path (clean fork from `~/.sc/`).
- `~/.melt/<skill>/meta.md` — native overlay manifest.
- `~/.melt/<skill>/N-melting-pot/` — tier dirs (suffix mandatory per Q-007).
- `~/.melt/<skill>/patches/` — git patches against upstream content (numbered NNN-).
- `~/.melt/<skill>/patches/.failed/` — failure markers (LLM-triaged by `mp:learn patch-triage`).
- `~/.melt/.trash/<ISO-ts>-<dirname>/` — soft-deleted skills with `.mp-trash-meta.json`.

## Edge cases

- **Exact-name collision in Step 2**: default to update unless user says "create new with a different name".
- **`validate` fails after create/update**: do NOT confirm success. Fix issues, re-run, then continue.
- **`patch-validate` shows everything `failed`**: probably an upstream rewrite invalidated the patches. Bring them up with `mp:learn patch-triage`.
- **bare `N/` tier dir present**: validate warns; rename to `N-melting-pot/` to fix (Q-007).

## Related

- `mp:search` — search engine. Used in Step 2.
- `mp:list` — flat inventory. Useful before bulk edits.
- `mp:load` — read a skill's full content (manifest + chunks + applied patches).
- `mp:learn patch-triage` — propose fixes for failed patches LLM-style.
- `~/.melt/lib/discover.sh`, `tier.sh`, `patch.sh` — shared helpers this script delegates to.
