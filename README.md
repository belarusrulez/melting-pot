# melting-pot

**Your skills, but they evolve.** A small set of meta-skills register with your agent; every other skill stays a plain `SKILL.md` on disk, found by full-path lookup at the moment of need. On top of that, a **tiered overlay** lets skills grow, shrink, and get patched as you actually use them. No daemon, no embeddings, no proprietary store — just files in your filesystem and `sqlite3`.

⭐ Star the repo if it saved you some pain. Open an issue if it glitches anywhere.

## TL;DR

You have skills scattered across folders. Some you wrote, some you didn't, none are searchable, and the good ones never improve. melting-pot registers five meta-skills with your agent and lets every other skill live wherever you keep it:

- **`mp:search`** — *ranked fuzzy retrieval.* Multi-axis search (literal / synonym / intent, merged with Reciprocal Rank Fusion) that finds the right skill for the task across every repo you've pointed it at. *"I need a skill for X."*
- **`mp:list`** — *flat catalog.* Complete, deterministic inventory — the catalog view to `mp:search`'s ranked view. *"What do I even have?"*
- **`mp:crud`** — *managing the skills.* Create, validate, trash/restore skills; add/remove/validate patches over upstream skills you don't own.
- **`mp:load`** — *compose.* Assemble a skill's full content — manifest + tier chunks + applied patches — as markdown or JSON.
- **`mp:learn`** — *evolution.* Promote chunks that earn their keep to higher tiers, demote (and eventually drop) the ones that don't, harvest new chunks from a session, and triage patches that stopped applying.

## How it works

**Skills live in *your* filesystem, in a vendor-neutral location** — not in `~/.claude/skills/`, not in `.cursor/rules/`, not in any tool's proprietary store. Switch agents and your skills come with you. Same files, different harness.

The search is intentionally cheap and robust. The user describes a task in one vocabulary; the skill author wrote the description in another — *skill named "Extract structured data from PDFs", user says "pull tables out of this report."* Same task, zero shared keywords. melting-pot expands the query into three axes (literal phrase, synonym/jargon, intent/goal), runs each as a full-text search, and merges the rankings with Reciprocal Rank Fusion. The skill that ranks middling on all three axes beats the one that ranks #1 on a single axis and is absent on the others. No model dependency, no index to babysit.

What makes a skill *evolve*:

- **Tiers (`0-melting-pot/` … `5-melting-pot/`).** A skill is a stack of chunks at tiers 0–5. Higher tier = more load-bearing. `mp:load` composes them top-down; the search index folds every tier's content into one ranked row.
- **Patches over upstream.** Keep a `patches/` stack against a skill you don't own. They apply in-memory at compose/index time; a patch that stops applying is recorded to `patches/.failed/` and the pipeline keeps going (never auto-stops) — `mp:learn patch-triage` walks the failures and proposes fixes.
- **Usage-driven movement.** `mp:learn promote`/`demote` move chunks between tiers based on how they actually get used. No rule grammar — you (or the agent) decide, the tool records the history.
- **Clean overlay at `~/.melt/`.** Your edits live in an overlay separate from the upstream source, which stays read-only.

## Install

Paste this into a fresh agent session:

> Bootstrap melting-pot on this machine: ask me where to clone `git@github.com:belarusrulez/melting-pot.git` (suggest the directory where you started as the default), then follow `install/INSTALL.md` → **Bootstrap on a fresh machine**, in order. `install/install.sh` does the deterministic filesystem work (seeds `~/.melt/`, symlinks each skill's `action` into `~/.melt/<skill>/action`, copies the hooks, emits the hook manifest + task-intake landing). Two steps are yours because they're harness-specific: **(a)** register every shipped skill — discover them with `find "$REPO/mp" -mindepth 2 -maxdepth 2 -name SKILL.md` and register each one the way your harness expects; **(b)** register the two hooks listed in `~/.melt/REGISTER-HOOKS.md` and append `~/.melt/task-intake.md` to your global rules file. Then build the index and smoke-test (`sh ~/.melt/search/action reindex` ; `sh ~/.melt/list/action --count`). After registering the skills, tell me which ones registered (by their frontmatter `name:`). Don't commit anything.

See [install/INSTALL.md](install/INSTALL.md) for the annotated walkthrough with rationale, the full layout diagram, and notes on each step.

## Uninstall

Paste this into an agent session:

> Uninstall melting-pot on this machine — do every step without asking for confirmation. (1) Unregister every skill the installer added from `$REPO/mp/`: discover them the same way (`find "$REPO/mp" -mindepth 2 -maxdepth 2 -name SKILL.md`), then remove each via your harness's mechanism. (2) Unregister the two hooks (`melt-nudge.sh`, `melt-resume.sh`) from your harness config. (3) Remove the `## Task intake` block the installer added to your global rules file — resolve the path first (it may be a symlink; edit the real target). (4) Remove the runtime tree: `rm -rf ~/.melt/`. Leave the cloned source repo on disk — print its path and tell me to `rm -rf` it myself if I want the source gone. Source repos listed in `~/.melt/repos.patterns` are never touched.

## Day-to-day usage

If you know a skill is needed, just include `mp:search` in your prompt — or let the agent search on its own when it senses a skill would help. To evolve a skill after a session, reach for `mp:learn` (promote/demote/harvest); to compose one for reading, `mp:load`.

## Requirements

- **macOS** — verified. Everything the bootstrap uses (`/bin/sh`, `sqlite3`, `git`, `find`, `grep`, `awk`, `sed`, `readlink`, `ln -s`, `mktemp`) ships with macOS 14+.
- **Linux** — works on standard distros (POSIX `sh` + coreutils). Needs `sqlite3` ≥ 3.20 for FTS5. Open an issue on portability bugs.
- **Windows** — use WSL for now.
- An agent that loads skills from a per-skill `SKILL.md` file (Claude Code, Cursor, Cline, anything compatible).

## License

MIT.
