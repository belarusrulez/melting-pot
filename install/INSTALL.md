# INSTALL — melting-pot bootstrap

## Platform support

- **macOS** — tested. Everything used by the bootstrap is preinstalled on 14+.
- **Linux** — should work (POSIX `sh` + standard coreutils); needs `sqlite3` ≥ 3.20 for FTS5. Untested in CI — open an issue if you hit a portability bug.
- **Windows** — runs natively under **Git Bash / MSYS2** (ships with [Git for Windows](https://gitforwindows.org/)); WSL also works. Invoke everything through `sh` (e.g. `sh ~/.melt/search/action …`), exactly as on macOS/Linux. Two platform differences are handled for you:
  - **`sqlite3` is not bundled with Windows.** Install it and put it on `PATH` before step 7: `winget install SQLite.SQLite` (reopen the shell afterwards), `scoop install sqlite`, `choco install sqlite`, or the [precompiled tools zip](https://sqlite.org/download.html). `sh ~/.melt/search/action doctor` reports whether it's found.
  - **Symlinks degrade to shims/mirrors.** When the shell can't create real symlinks (the MSYS default), `install.sh` writes a shim `action` per skill (execs the real repo action with `MP_LIB_DIR` set — still live) and discovery **mirrors** upstream `N-melting-pot/` tier dirs instead of symlinking them. Everything downstream behaves identically. To get real symlinks instead, enable Windows Developer Mode and export `MSYS=winsymlinks:nativestrict`.

> **Agent?** This is the annotated walkthrough. The one-paste install prompt lives in the [README](../README.md#install--update) — that's where most users start. To run the bootstrap, do **§ Bootstrap on a fresh machine** below in order with `Bash`; each command stands alone.
>
> The split to keep in mind: **`install/install.sh` does everything deterministic** (seeds `~/.melt/`, symlinks each skill's `action`, copies hooks, emits the hook manifest). **You** own only the two harness-specific steps it can't portably script:
>
> - **Step 4** — register every `mp/*/SKILL.md` with your harness.
> - **Step 6** — register the two hooks.
>
> After step 4, list the registered skills back to the user by their frontmatter `name:`. Don't commit anything.

This repo ships its meta-skills under `mp/`. Each subdirectory of `mp/` that contains a `SKILL.md` is a skill — the installer symlinks its `action` and you register the `SKILL.md`. Currently shipped:

- **`mp-search`** — multi-axis skill search across registered repos (the ranked view).
- **`mp-list`** — flat inventory of every registered skill (the catalog view).
- **`mp-crud`** — skill lifecycle (scaffold, validate, trash/restore, patch-add/list/remove/validate).
- **`mp-load`** — compose a skill's full content (manifest + tier chunks + applied patches) as markdown or JSON.
- **`mp-learn`** — usage-driven tier movement (promote/demote/cascade), duplicate refactor proposals, harvest, and failed-patch triage.

If a new skill is later added under `mp/`, re-running `install.sh` re-creates the symlinks and you re-run step 4 to register it.

## Design in one paragraph

melting-pot puts a **tiered overlay** on top of plain skill search: every skill can carry `N-melting-pot/` tier dirs (0–5) and a `patches/` stack, and the search index folds chunk + patch content into one FTS5 row. Runtime state lives under `~/.melt/` (config, overlays, index, learn state); discovery reads **only** `~/.melt/repos.patterns`, with no other runtime config path (Q-008). Harness-registration of the meta-skills is the only agent-side step; once `~/.melt/repos.patterns` points at a root, `mp-search`/`mp-list` find everything under it by full path. `install.sh` keeps the deterministic work in one auditable script and never touches harness config (Q-003).

## Layout

```
/<repo>/melting-pot/                 ← this repo
├── INSTALL.md                       ← this file
├── mp/
│   ├── lib/                         ← shared shell helpers (discover/tier/patch/compose)
│   ├── search/{SKILL.md,action}     ← mp-search
│   ├── list/{SKILL.md,action}       ← mp-list
│   ├── crud/{SKILL.md,action}       ← mp-crud
│   ├── load/{SKILL.md,action}       ← mp-load
│   └── learn/{SKILL.md,action}      ← mp-learn
├── install/
│   ├── install.sh                   ← deterministic bootstrap (seed + symlink + hooks + manifest)
│   ├── REGISTER-HOOKS.md            ← hook manifest (human-readable placeholder)
│   └── hooks/{melt-nudge.sh,melt-resume.sh}
└── test/run-tests.sh                ← test harness (97 tests)

~/.melt/                             ← runtime state (created by install.sh)
├── repos.patterns                   ← user-edited list of skill source roots
├── <skill>/action → /<repo>/melting-pot/mp/<skill>/action   ← symlinked CLI (shim that execs the same path on Windows)
├── search/index.db                  ← FTS5 index, rebuilt atomically
├── learn/                           ← session state (.tool-count-*, .pending-transcript)
├── hooks/{melt-nudge.sh,melt-resume.sh}   ← copied hook scripts
├── REGISTER-HOOKS.md                ← emitted manifest (absolute paths baked in)
└── trash/                           ← soft-deleted skills

<your harness's skill-registration mechanism>:   ← you register every SKILL.md under mp/
  mp-search  →  /<repo>/melting-pot/mp/search/SKILL.md
  mp-list    →  /<repo>/melting-pot/mp/list/SKILL.md
  ...        (other skills already registered with your harness stay as-is)
```

## Bootstrap on a fresh machine (or update an existing checkout)

**Install and update are the same flow — run these steps top to bottom either way.** On a fresh machine they install; on a machine that already has melting-pot they update. Every step is idempotent: step 1 pulls the latest source if you're already in the clone, step 3's installer re-seeds and refreshes symlinks/hooks/manifests, and the harness-owned steps (4, 6) re-sync rather than duplicate (register only newly-added skills, refresh hooks if their content changed). So a user updating to a new version just pastes the same prompt again.

1. **Locate the repo — detect an existing clone before asking to clone.** Run this first; it sets `REPO` either to the clone you're already in or to a fresh clone, and only prompts when neither applies (requires GitHub SSH access — `ssh -T git@github.com` should succeed — only when it actually clones):

   ```sh
   if root=$(git rev-parse --show-toplevel 2>/dev/null) \
      && url=$(git -C "$root" remote get-url origin 2>/dev/null) \
      && printf '%s' "$url" | grep -Eq '[:/]belarusrulez/melting-pot(\.git)?$'; then
     # Already inside the correct clone — reuse it, don't ask where to clone.
     REPO="$root"
     git -C "$REPO" fetch --quiet 2>/dev/null || true
     if [ -n "$(git -C "$REPO" rev-list HEAD..@{u} 2>/dev/null)" ]; then
       # Behind upstream — this is an UPDATE. Pull latest, then re-run the
       # rest of the steps; they're idempotent and will refresh everything.
       if git -C "$REPO" pull --ff-only --quiet; then
         echo "REPO=$REPO (updated to latest — re-applying steps to refresh)"
       else
         echo "REPO=$REPO (behind, but pull --ff-only failed — local commits or dirty tree; resolve manually, then re-run)"
       fi
     else
       echo "REPO=$REPO (up to date — proceeding without prompts)"
     fi
   else
     # Not inside the repo — THEN ask the user which parent dir to clone into
     # (suggest the dir where the LLM started as the default), and from there:
     git clone git@github.com:belarusrulez/melting-pot.git
     REPO="$(pwd)/melting-pot"
   fi
   ```

   When the detection branch fires (already in a clean, up-to-date `belarusrulez/melting-pot` checkout), **do not ask where to clone** — that question only applies to the `else` branch.

2. **Verify dependencies** (preinstalled on macOS 14+ and most Linux; on Windows install `sqlite3` first — see **Platform support** above):

   ```sh
   sqlite3 --version | grep -q '3\.[0-9][0-9]'   # FTS5 needs sqlite3 ≥ 3.20
   sh -c 'true'                                  # POSIX sh works (Git Bash on Windows)
   ```

3. **Run the deterministic installer.** It seeds `~/.melt/`, symlinks each skill's `action` into `~/.melt/<skill>/action` (or writes a shim where symlinks aren't available, e.g. Windows/MSYS), copies the hooks, and emits the hook manifest. Preview first with `--dry-run`:

   ```sh
   sh "$REPO/install/install.sh" --dry-run            # preview
   sh "$REPO/install/install.sh"                      # apply
   ```

   After this, `~/.melt/<skill>/action` resolves for all five skills. The installer never writes to `~/.claude/settings.json` (Q-003) — steps 4 and 6 are yours.

4. **Register every skill under `$REPO/mp/` with your harness.** A skill = any subdirectory of `$REPO/mp/` containing a `SKILL.md` (the frontmatter `name:` is the skill's name). Discover them with:

   ```sh
   find "$REPO/mp" -mindepth 2 -maxdepth 2 -name SKILL.md
   ```

   Register each `SKILL.md` found as a plain **personal** skill, using whatever mechanism your harness expects — you know how. Register them all the same way. The frontmatter names are hyphenated (`mp-search`, `mp-list`, `mp-crud`, `mp-load`, `mp-learn`) on purpose: some harnesses reserve the colon for plugin namespacing (Claude Code is one), so a personal skill named `mp:search` would **not** yield a `/mp:search` command there. The hyphen form registers cleanly as a personal skill on any harness (Claude Code: `/mp-search` works) with no plugin packaging. Do not rewrite the names to colons or wrap them in a plugin. These are the only skills this installer adds; anything else already registered with the harness is left untouched (`mp-search`/`mp-list` discover those via `~/.melt/repos.patterns` when their root is listed). Confirm the registered skills back to the user by name. **On update:** re-registering an already-registered skill is harmless; the point is to pick up any skill a new version added under `$REPO/mp/` (the `find` above lists the current set).

5. **Seed `~/.melt/repos.patterns`.** The installer wrote a sample. Register melting-pot's own `mp/` root so the meta-skills are discoverable, then **ask the user which additional roots to register** (their existing skills dir, per-project skill dirs, etc.). One entry per line, `<abs-root><TAB><pattern>` (default pattern `*`; prefix `re:` for regex):

   ```sh
   printf '%s\t*\n' "$REPO/mp" >> ~/.melt/repos.patterns
   # plus any roots the user names, e.g.:
   #   printf '%s\t*\n' "$HOME/Projects/my-skills" >> ~/.melt/repos.patterns
   ```

   Adding a root only indexes the skills there — it does not touch, move, or unregister them. Roots support `~`/`~/…` (portable across machines); avoid machine-specific absolute paths if you want the file to travel. **On update:** the file already exists with the user's roots — don't clobber it; only append a line if that exact root isn't already present (e.g. `grep -qF "$REPO/mp" ~/.melt/repos.patterns || printf '%s\t*\n' "$REPO/mp" >> ~/.melt/repos.patterns`).

6. **Register the hooks.** Read the emitted manifest and translate each row into your harness's hook config (the installer does NOT do this — Q-003):

   ```sh
   cat ~/.melt/REGISTER-HOOKS.md
   ```

   - `melt-nudge.sh` → `Stop` event (nudges `mp-learn` before `/clear`).
   - `melt-resume.sh` → `SessionStart:clear` event (stages the prior transcript for `mp-learn harvest --transcript`).

   Claude Code: add each to the matching slot in `~/.claude/settings.json`. **On update:** if the hooks are already wired to the same `~/.melt/hooks/*.sh` paths, leave the config as-is — step 3 already refreshed the script contents in place, so no harness change is needed unless the event/path changed.

7. **Build the index + smoke test:**

   ```sh
   sh ~/.melt/search/action reindex
   sh ~/.melt/search/action "search a skill" "find skill by name" "skill discovery"
   sh ~/.melt/list/action --count
   sh ~/.melt/crud/action validate "$REPO/mp/list"
   ```

   The first search should show the bundled meta-skills (`mp-search`, `mp-list`, …) near the top of the Convergence section. `--count` should print the total skill count discovered across `~/.melt/repos.patterns`. `validate` should print `OK: …/mp/list`. If anything looks wrong, recheck `~/.melt/repos.patterns` and run `sh ~/.melt/search/action doctor`.

## Day-to-day usage

When the user asks "do I have a skill for X", "find a skill that…", **invoke `mp-search`** — always three queries (literal, synonym, intent):

```sh
sh ~/.melt/search/action "<literal phrase>" "<synonym/jargon>" "<intent/goal>"
```

It returns a `Convergence` section (skills matching 2+ axes — strongest signal) and `Single-axis hits`, each with a `→ <full path>` line. **Read the `SKILL.md` (or `meta.md`) at that path** and follow its instructions.

Other entry points:

```sh
sh ~/.melt/list/action                          # full inventory (text)
sh ~/.melt/list/action --format json            # machine-readable
sh ~/.melt/load/action <skill> --format md      # compose full skill content
sh ~/.melt/crud/action validate <skill>         # lifecycle + patch ops (see its SKILL.md)
sh ~/.melt/learn/action promote <chunk>         # tier movement (see its SKILL.md)
```

## What this installer does NOT touch

- Other skills already registered with your harness. They keep working. To let `mp-search` find them too, add their directory to `~/.melt/repos.patterns`.
- Source repos listed in `~/.melt/repos.patterns`. Only their index is rebuilt; the files themselves are read-only to melting-pot.
- Harness config (`~/.claude/settings.json` etc.). The installer asserts the Q-003 invariant at exit and aborts if breached.

## Note on slash-commands

`/<skill-name>` only works for skills the harness itself has registered (including every skill you add from `$REPO/mp/` in step 4). Skills discovered via `mp-search`/`mp-list` are read by full path and followed by the agent — there is no slash-command for them.

## Uninstall

1. Unregister every skill added from `$REPO/mp/` (reverse step 4 — discover the same way: `find "$REPO/mp" -mindepth 2 -maxdepth 2 -name SKILL.md`).
2. Unregister the two hooks from your harness config.
3. Remove the runtime tree:

   ```sh
   rm -rf ~/.melt/
   ```

Source repos and the cloned `melting-pot` repo are untouched — delete the clone manually if you no longer want the source.
