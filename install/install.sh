#!/bin/sh
# install/install.sh — melting-pot bootstrap.
#
# What it does (per Q-003, Q-008, Q-012, Q-013):
#   - Seeds the ~/.melt/ overlay root + hook copies + (optional) task-intake
#     rule landing point.
#   - Emits a HARNESS-AGNOSTIC manifest (install/REGISTER-HOOKS.md, single
#     markdown file with one row per hook). The calling LLM reads that file
#     and translates each row into whatever its harness needs (Claude Code:
#     `~/.claude/settings.json` ; Cursor: `.cursorrules` ; Codex: …).
#   - NEVER writes to `~/.claude/settings.json` or any other harness config
#     file. That's the calling LLM's job. See Q-003.
#   - Bundled installer (Q-013): the same script also installs the
#     task-intake CLAUDE.md rule by copying `install/task-intake.md` to
#     `$MP_HOME/task-intake.md` and printing a "Next steps" message telling
#     the calling LLM to append it to the harness's global rules file.
#
# Flags:
#   --dry-run         — print what would happen; do not write anything.
#   --copy-from-sc    — one-time migration: cp ~/.sc/repos.patterns →
#                       $MP_PATTERNS if destination is missing. No-op
#                       otherwise. Per Q-008 (clean fork, no runtime
#                       fallback).
#   --emit-manifest-only
#                     — write the manifest + task-intake landing, skip
#                       everything else (seed, copy hooks). Useful for
#                       refreshing the manifest after a melting-pot upgrade.
#   -h, --help        — show usage.
#
# Environment overrides (also honoured by the hooks they install):
#   MP_HOME      — overlay root (default: $HOME/.melt)
#   MP_PATTERNS  — repos.patterns path (default: $MP_HOME/repos.patterns)
#   MP_INSTALL_ROOT — repo root containing install/ + mp/ (default: auto-
#                     detected from this script's location)
#
# Exit status:
#   0 — success or harmless no-op
#   2 — invalid flag / unknown subcommand
#   3 — required source file missing (e.g. install/task-intake.md not found)

set -u

# ----- locate this script + project root -----
SELF=$(cd "$(dirname "$0")" && pwd)
MP_INSTALL_ROOT=${MP_INSTALL_ROOT:-$(cd "$SELF/.." && pwd)}

# ----- defaults -----
MP_HOME=${MP_HOME:-$HOME/.melt}
MP_PATTERNS=${MP_PATTERNS:-$MP_HOME/repos.patterns}
MP_NUDGE_THRESHOLD=${MP_NUDGE_THRESHOLD:-20}

DRY_RUN=0
COPY_FROM_SC=0
MANIFEST_ONLY=0

# ----- small helpers -----
info()    { printf 'info:    %s\n' "$*"; }
warn()    { printf 'warn:    %s\n' "$*" >&2; }
err()     { printf 'error:   %s\n' "$*" >&2; }
action()  {
  # $1 = label (e.g. "mkdir", "cp", "write"), rest = description
  lbl="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN  %-7s %s\n' "$lbl" "$*"
  else
    printf 'do       %-7s %s\n' "$lbl" "$*"
  fi
}

usage() {
  cat <<USAGE
usage: install.sh [--dry-run] [--copy-from-sc] [--emit-manifest-only] [-h|--help]

Bootstraps the melting-pot overlay at \$MP_HOME (default ~/.melt) and emits
a HARNESS-AGNOSTIC manifest the calling LLM reads to register the hook
scripts in whatever harness it speaks (Claude Code, Cursor, Codex, etc.).

This script never writes to ~/.claude/settings.json. See Q-003.
USAGE
}

# ----- arg parse -----
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)             DRY_RUN=1; shift ;;
    --copy-from-sc)        COPY_FROM_SC=1; shift ;;
    --emit-manifest-only)  MANIFEST_ONLY=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    --)                    shift; break ;;
    -*)                    err "unknown flag: $1"; usage >&2; exit 2 ;;
    *)                     err "unexpected positional: $1"; usage >&2; exit 2 ;;
  esac
done

# ----- safety guard: refuse to write to harness config -----
# Even though we never deliberately touch ~/.claude/settings.json, we make
# the invariant testable by recording the path here and checking it at exit.
HARNESS_CONFIG="$HOME/.claude/settings.json"
HARNESS_BEFORE_HASH=""
if [ -f "$HARNESS_CONFIG" ]; then
  HARNESS_BEFORE_HASH=$(shasum "$HARNESS_CONFIG" 2>/dev/null | awk '{print $1}')
fi

# ----- I/O wrappers respecting --dry-run -----
do_mkdir() {
  d="$1"
  action mkdir "$d"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$d"
}
do_cp() {
  src="$1"; dst="$2"
  action cp "$src -> $dst"
  [ "$DRY_RUN" = 1 ] && return 0
  cp "$src" "$dst"
}
do_write() {
  # $1 = destination path; stdin = content
  dst="$1"
  action write "$dst"
  if [ "$DRY_RUN" = 1 ]; then
    cat > /dev/null
    return 0
  fi
  cat > "$dst"
}

# ----- step 1: seed $MP_HOME, repos.patterns, learn dir -----
if [ "$MANIFEST_ONLY" = 0 ]; then
  do_mkdir "$MP_HOME"
  do_mkdir "$MP_HOME/learn"
  do_mkdir "$MP_HOME/hooks"
  do_mkdir "$MP_HOME/search"
  do_mkdir "$MP_HOME/trash"

  # repos.patterns: only write a stub if both --copy-from-sc was NOT used and
  # the destination is missing. We never overwrite an existing patterns file.
  if [ ! -e "$MP_PATTERNS" ] && [ "$COPY_FROM_SC" = 0 ]; then
    action write "$MP_PATTERNS (sample)"
    if [ "$DRY_RUN" = 0 ]; then
      cat > "$MP_PATTERNS" <<'PATTERNS'
# melting-pot — registered skill roots.
# One entry per line: <root>\t<pattern>
# <pattern> is a glob applied to immediate children of <root>; default '*'.
#
# Examples:
#   $HOME/skills	*
#   $HOME/work/skill-core/test/skills	*
PATTERNS
    fi
  fi

  # --copy-from-sc: one-time migration. Only fires if destination is missing
  # AND the source exists. Idempotent — re-runs are no-ops.
  if [ "$COPY_FROM_SC" = 1 ]; then
    sc_src="$HOME/.sc/repos.patterns"
    if [ -e "$MP_PATTERNS" ]; then
      info "--copy-from-sc: destination $MP_PATTERNS already exists; no-op"
    elif [ ! -e "$sc_src" ]; then
      warn "--copy-from-sc: source $sc_src not found; nothing to migrate"
    else
      do_cp "$sc_src" "$MP_PATTERNS"
      info "migrated $sc_src -> $MP_PATTERNS"
    fi
  fi

  # Hook scripts → $MP_HOME/hooks/ (copied so the manifest can reference a
  # stable path independent of the repo's working directory).
  for hook in melt-nudge.sh melt-resume.sh; do
    src="$MP_INSTALL_ROOT/install/hooks/$hook"
    dst="$MP_HOME/hooks/$hook"
    if [ ! -f "$src" ]; then
      err "missing hook source: $src"
      exit 3
    fi
    do_cp "$src" "$dst"
    if [ "$DRY_RUN" = 0 ]; then
      chmod +x "$dst" 2>/dev/null || :
    fi
  done
fi

# ----- step 2: emit the manifest (Q-012: markdown only, single file) -----

manifest_src="$MP_INSTALL_ROOT/install/REGISTER-HOOKS.md"
# The manifest lives alongside the installer source for the calling LLM to
# read directly. We ALSO emit a copy under $MP_HOME with the active script
# paths baked in, so the calling agent can read accurate absolute paths
# without re-running the installer.
#
# By default the installer writes a sandbox-safe copy at
# $MP_HOME/REGISTER-HOOKS.md and leaves install/REGISTER-HOOKS.md unchanged
# (the repo-side copy is a placeholder using `~/.melt/...`). To overwrite
# the repo-side manifest, set MP_EMIT_MANIFEST_TO an explicit path or pass
# --emit-to <path>.
emit_manifest_dst="${MP_EMIT_MANIFEST_TO:-$MP_HOME/REGISTER-HOOKS.md}"

nudge_path="$MP_HOME/hooks/melt-nudge.sh"
resume_path="$MP_HOME/hooks/melt-resume.sh"
task_intake_dst="$MP_HOME/task-intake.md"

if [ "$DRY_RUN" = 1 ]; then
  action write "$emit_manifest_dst (manifest)"
else
  action write "$emit_manifest_dst (manifest)"
  manifest_dir=$(dirname "$emit_manifest_dst")
  [ -d "$manifest_dir" ] || mkdir -p "$manifest_dir"
  cat > "$emit_manifest_dst" <<MANIFEST
# REGISTER-HOOKS.md — melting-pot hook manifest

> Emitted by \`install/install.sh\`. The calling LLM reads this file and
> translates each row below into whatever the active harness needs.
>
> **This file is the source of truth.** The installer does NOT mutate
> harness config (Q-003). Translation responsibilities live with the
> calling LLM.

## What the calling LLM should do

For each row in **Hooks** below:

1. Read the **Script** path and **Hook event** slot.
2. Register the script in the active harness's config so it fires on that
   event. Examples by harness:
   - **Claude Code:** append an entry to \`hooks.<event>\` in
     \`~/.claude/settings.json\`. (Use the \`update-config\` skill if
     available, or hand-edit.)
   - **Cursor:** add a rule in \`.cursorrules\` that runs the script at
     the equivalent moment.
   - **Codex / others:** consult that harness's hook docs.
3. After all hook rows are registered, follow **Task-intake rule** below
   to append the global-rule snippet to the harness's global rules file.

Verify each registration by triggering the corresponding event once and
confirming the script's stdout reaches the agent.

## Hooks

| Script | Hook event | Purpose | Install-target hint |
| --- | --- | --- | --- |
| \`$nudge_path\` | \`Stop\` | After each assistant turn ends, nudges the agent (once per session, after $MP_NUDGE_THRESHOLD tool calls — \`MP_NUDGE_THRESHOLD\` env overrides) to run \`mp:learn\` before \`/clear\`. Plain-text stdout; harness-agnostic. | Claude Code: add to \`hooks.Stop\` in \`~/.claude/settings.json\`. |
| \`$resume_path\` | \`SessionStart:clear\` | When a session is cleared, writes the prior transcript path to \`\$MP_HOME/learn/.pending-transcript\` and emits a resume-or-harvest prompt. \`mp:learn harvest --transcript\` consumes the handshake via read-then-unlink. | Claude Code: add to \`hooks.SessionStart\` with matcher \`clear\` in \`~/.claude/settings.json\`. |

## Task-intake rule

The installer also drops \`$task_intake_dst\` — a markdown snippet that
forces a 3-rephrasing + \`mp:search\` step before any new task. The
calling LLM should append the contents of that file to the harness's
global rules file:

- **Claude Code:** append to \`~/.claude/CLAUDE.md\` (or the user's
  \`CLAUDE.md\` of choice).
- **Cursor:** append to \`.cursorrules\`.
- **Codex / others:** equivalent global-rules file.

Verify by starting a new conversation: the next user prompt should
trigger the rephrasing pass before any other action.

## Sanity checklist for the calling LLM

- [ ] Both hook scripts are executable (\`chmod +x\` already applied by the
      installer; re-check if you copied them elsewhere).
- [ ] Their absolute paths are reachable from the harness (no \`~\` in the
      registration unless the harness expands it).
- [ ] The harness fires the matching event when expected (see harness docs).
- [ ] The task-intake snippet is appended exactly once to the global rules
      file (don't duplicate).

## When to re-emit this manifest

Run \`install.sh --emit-manifest-only\` after:

- Changing \`\$MP_HOME\` (script paths in the table will refresh).
- Upgrading melting-pot to a new version that ships additional hooks.

The script is idempotent; re-running is safe.
MANIFEST
fi

# Also write task-intake.md to its landing location ($MP_HOME/task-intake.md).
if [ "$MANIFEST_ONLY" = 0 ] || [ "$MANIFEST_ONLY" = 1 ]; then
  ti_src="$MP_INSTALL_ROOT/install/task-intake.md"
  if [ ! -f "$ti_src" ]; then
    err "missing task-intake source: $ti_src"
    exit 3
  fi
  do_cp "$ti_src" "$task_intake_dst"
fi

# ----- step 3: verify harness config was NOT mutated (Q-003 invariant) -----
if [ -f "$HARNESS_CONFIG" ]; then
  AFTER_HASH=$(shasum "$HARNESS_CONFIG" 2>/dev/null | awk '{print $1}')
  if [ "$AFTER_HASH" != "$HARNESS_BEFORE_HASH" ]; then
    err "INVARIANT BREACH: $HARNESS_CONFIG was modified by this installer."
    err "  before: $HARNESS_BEFORE_HASH"
    err "  after:  $AFTER_HASH"
    err "  This violates Q-003. The bug is in install.sh; do not ship."
    exit 4
  fi
elif [ -n "$HARNESS_BEFORE_HASH" ]; then
  err "INVARIANT BREACH: $HARNESS_CONFIG was removed by this installer."
  exit 4
fi

# ----- step 4: print "Next steps" for the calling LLM -----
cat <<NEXT

Next steps — the CALLING LLM should now:

  1. Read $emit_manifest_dst
     (or the repo-side placeholder at $manifest_src for the human-readable
     version with \`~/.melt/...\` paths).
  2. For each row under '## Hooks', register the script at the listed event
     slot in the active harness (Claude Code: ~/.claude/settings.json;
     Cursor: .cursorrules; etc.).
  3. Append the contents of $task_intake_dst to the harness's global rules
     file (Claude Code: ~/.claude/CLAUDE.md).

This installer DELIBERATELY does NOT mutate ~/.claude/settings.json or any
other harness config. That is the calling LLM's job (Q-003).

NEXT

exit 0
