#!/bin/sh
# install/install.sh — melting-pot bootstrap.
#
# What it does (per Q-003, Q-008, Q-012):
#   - Seeds the ~/.melt/ overlay root + hook copies.
#   - Emits a HARNESS-AGNOSTIC manifest (install/REGISTER-HOOKS.md, single
#     markdown file with one row per hook). The calling LLM reads that file
#     and translates each row into whatever its harness needs (Claude Code:
#     `~/.claude/settings.json` ; Cursor: `.cursorrules` ; Codex: …).
#   - NEVER writes to `~/.claude/settings.json` or any other harness config
#     file. That's the calling LLM's job. See Q-003.
#
# Flags:
#   --dry-run         — print what would happen; do not write anything.
#   --emit-manifest-only
#                     — write the manifest only, skip
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
#   3 — required source file missing (e.g. install/hooks/melt-nudge.sh not found)

set -u

# ----- locate this script + project root -----
SELF=$(cd "$(dirname "$0")" && pwd)
MP_INSTALL_ROOT=${MP_INSTALL_ROOT:-$(cd "$SELF/.." && pwd)}

# ----- defaults -----
MP_HOME=${MP_HOME:-$HOME/.melt}
MP_PATTERNS=${MP_PATTERNS:-$MP_HOME/repos.patterns}
MP_NUDGE_THRESHOLD=${MP_NUDGE_THRESHOLD:-20}

DRY_RUN=0
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

# Portable SHA-256 of a file → hex digest only (no filename). Tries shasum
# (macOS), sha256sum (Linux/Git-Bash), then openssl. Used only for the Q-003
# before/after invariant check, so any stable algorithm works.
_sha256_file() {
  f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}'
  fi
}

usage() {
  cat <<USAGE
usage: install.sh [--dry-run] [--emit-manifest-only] [-h|--help]

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
  HARNESS_BEFORE_HASH=$(_sha256_file "$HARNESS_CONFIG")
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
do_ln() {
  src="$1"; dst="$2"
  action ln "$src -> $dst"
  [ "$DRY_RUN" = 1 ] && return 0
  ln -sf "$src" "$dst"
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

# Probe (memoised) whether real symlinks can be created here. On Windows under
# Git Bash / MSYS2 without native-symlink support, `ln -s` silently makes a COPY
# and `[ -L ]` is false — this detects exactly that.
_symlinks_supported() {
  case "${_SYMLINKS_OK:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  _probe=$(mktemp -d 2>/dev/null) || { _SYMLINKS_OK=0; return 1; }
  if ln -s "$_probe/target" "$_probe/link" 2>/dev/null && [ -L "$_probe/link" ]; then
    _SYMLINKS_OK=1
  else
    _SYMLINKS_OK=0
  fi
  rm -rf "$_probe" 2>/dev/null
  [ "$_SYMLINKS_OK" = 1 ]
}

# do_link_action <real-action> <dst> — make `sh <dst>` run <real-action> with
# its sibling lib/ resolvable. On macOS/Linux this is a symlink (so repo edits
# stay live and `readlink` resolves the lib path). On Windows/MSYS, where a
# symlink would become a stale copy that can't find ../lib, we instead write a
# tiny shim that exports MP_LIB_DIR and execs the real action — also live, and
# symlink-free. Both forms keep `sh ~/.melt/<skill>/action ...` working.
do_link_action() {
  src="$1"; dst="$2"
  if _symlinks_supported; then
    do_ln "$src" "$dst"
    return 0
  fi
  action shim "$src -> $dst"
  [ "$DRY_RUN" = 1 ] && return 0
  lib_dir=$(CDPATH= cd "$(dirname "$src")/../lib" 2>/dev/null && pwd) || lib_dir=""
  rm -f "$dst"
  {
    printf '#!/bin/sh\n'
    printf '# melting-pot action shim (symlink-free fallback for platforms\n'
    printf '# without native symlinks, e.g. Git Bash/MSYS2 on Windows).\n'
    printf '# Auto-generated by install/install.sh — re-run the installer to refresh.\n'
    [ -n "$lib_dir" ] && printf 'MP_LIB_DIR="%s"\n' "$lib_dir"
    [ -n "$lib_dir" ] && printf 'export MP_LIB_DIR\n'
    printf 'exec sh "%s" "$@"\n' "$src"
  } > "$dst"
  chmod +x "$dst" 2>/dev/null || :
}

# ----- step 1: seed $MP_HOME, repos.patterns, learn dir -----
if [ "$MANIFEST_ONLY" = 0 ]; then
  do_mkdir "$MP_HOME"
  do_mkdir "$MP_HOME/learn"
  do_mkdir "$MP_HOME/hooks"
  do_mkdir "$MP_HOME/search"
  do_mkdir "$MP_HOME/trash"

  # repos.patterns: write a stub only if the destination is missing. We never
  # overwrite an existing patterns file.
  if [ ! -e "$MP_PATTERNS" ]; then
    action write "$MP_PATTERNS (sample)"
    if [ "$DRY_RUN" = 0 ]; then
      cat > "$MP_PATTERNS" <<'PATTERNS'
# melting-pot — registered skill roots.
# One entry per line: <root>\t<pattern>
# <pattern> is a glob applied to immediate children of <root>; default '*'.
#
# Examples:
#   $HOME/skills	*
#   $HOME/Projects/melting-pot/mp	*
PATTERNS
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

  # Skill actions → $MP_HOME/<skill>/action. Each subdir of mp/ with a SKILL.md
  # is a shipped skill; symlink its `action` CLI so the SKILL.md invocation
  # `sh ~/.melt/<skill>/action` resolves. The SKILL.md files themselves are
  # registered with the harness by the calling LLM — see install/INSTALL.md.
  # NOTE: the do_* helpers assign bare globals (d/src/dst) — POSIX sh has no
  # function-local scope — so use a loop var (sd) they do not touch, and snapshot
  # the action path BEFORE calling do_mkdir (which would clobber it).
  for sd in "$MP_INSTALL_ROOT"/mp/*/; do
    [ -f "${sd}SKILL.md" ] || continue
    name=$(basename "$sd")
    skill_action="${sd}action"
    do_mkdir "$MP_HOME/$name"
    [ -f "$skill_action" ] && do_link_action "$skill_action" "$MP_HOME/$name/action"
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

Verify each registration by triggering the corresponding event once and
confirming the script's stdout reaches the agent.

## Hooks

| Script | Hook event | Purpose | Install-target hint |
| --- | --- | --- | --- |
| \`$nudge_path\` | \`Stop\` | After each assistant turn ends, nudges the agent (once per session, after $MP_NUDGE_THRESHOLD tool calls — \`MP_NUDGE_THRESHOLD\` env overrides) to run \`mp-learn\` before \`/clear\`. Plain-text stdout; harness-agnostic. | Claude Code: add to \`hooks.Stop\` in \`~/.claude/settings.json\`. |
| \`$resume_path\` | \`SessionStart:clear\` | When a session is cleared, writes the prior transcript path to \`\$MP_HOME/learn/.pending-transcript\` and emits a resume-or-harvest prompt. \`mp-learn harvest --transcript\` consumes the handshake via read-then-unlink. | Claude Code: add to \`hooks.SessionStart\` with matcher \`clear\` in \`~/.claude/settings.json\`. |

### Command format — POSIX vs Windows

The hook scripts carry a \`#!/bin/sh\` shebang and the executable bit, so the
\`command\` should be the **script path alone** — do NOT prefix it with \`sh \`.

- **macOS / Linux:** \`"command": "$nudge_path"\`.
- **Windows (Claude Code):** use the POSIX-style path (\`/c/Users/...\`, not
  \`C:\\Users\\...\`) and pin the Git Bash that runs hooks, otherwise a bare
  \`sh\` can resolve to an incompatible runtime and fail with
  \`/usr/bin/sh: ... cannot execute binary file\`. Add to \`~/.claude/settings.json\`:

  \`\`\`json
  "env": { "CLAUDE_CODE_GIT_BASH_PATH": "C:\\\\Program Files\\\\Git\\\\bin\\\\bash.exe" }
  \`\`\`

  then register the command as the script path alone (no \`sh\` prefix), e.g.
  \`"command": "$nudge_path"\`.

## Sanity checklist for the calling LLM

- [ ] Both hook scripts are executable (\`chmod +x\` already applied by the
      installer; re-check if you copied them elsewhere).
- [ ] Their absolute paths are reachable from the harness (no \`~\` in the
      registration unless the harness expands it).
- [ ] The harness fires the matching event when expected (see harness docs).

## When to re-emit this manifest

Run \`install.sh --emit-manifest-only\` after:

- Changing \`\$MP_HOME\` (script paths in the table will refresh).
- Upgrading melting-pot to a new version that ships additional hooks.

The script is idempotent; re-running is safe.
MANIFEST
fi

# ----- step 3: verify harness config was NOT mutated (Q-003 invariant) -----
if [ -f "$HARNESS_CONFIG" ]; then
  AFTER_HASH=$(_sha256_file "$HARNESS_CONFIG")
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

  1. Register every shipped skill with the harness. A skill = any subdir of
     $MP_INSTALL_ROOT/mp/ containing a SKILL.md; the frontmatter 'name:' is
     its name. Discover them with:
       find $MP_INSTALL_ROOT/mp -mindepth 2 -maxdepth 2 -name SKILL.md
     Register each SKILL.md the same way your harness expects. Their actions
     are already linked at \$MP_HOME/<skill>/action (a symlink, or a shim that
     execs the repo action where symlinks are unavailable, e.g. Windows/MSYS).
  2. Read $emit_manifest_dst
     (or the repo-side placeholder at $manifest_src for the human-readable
     version with \`~/.melt/...\` paths).
  3. For each row under '## Hooks', register the script at the listed event
     slot in the active harness (Claude Code: ~/.claude/settings.json;
     Cursor: .cursorrules; etc.).
  4. Build the index + smoke test:
       sh \$MP_HOME/search/action reindex
       sh \$MP_HOME/list/action --count

See $MP_INSTALL_ROOT/install/INSTALL.md for the full agent-run bootstrap.

This installer DELIBERATELY does NOT mutate ~/.claude/settings.json or any
other harness config. That is the calling LLM's job (Q-003).

NEXT

exit 0
