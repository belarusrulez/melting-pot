#!/bin/sh
# melt-nudge.sh — Stop-event hook for melting-pot.
#
# Harness-agnostic POSIX sh. Emits a plain-text nudge on stdout when the
# current session has crossed a tool-call activity threshold; the calling
# harness/agent decides what to do with the text.
#
# Per Q-003: this script makes NO Claude-Code-specific JSON assumptions. The
# installer's REGISTER-HOOKS.md tells the calling agent which harness slot to
# bind this to (e.g. Claude Code: `hooks.Stop`).
#
# Inputs (environment):
#   MP_HOME       — overlay root (default: ~/.melt)
#   MP_NUDGE_THRESHOLD — minimum tool-call count before nudging (default: 20)
#   MP_SESSION_ID — opaque session identifier (default: derived from $PPID
#                   so a parent agent's lifetime maps to one "session" when
#                   the harness doesn't supply a session id of its own)
#
# Inputs (positional, optional):
#   $1 — session id override (preferred over MP_SESSION_ID env)
#   $2 — tool-call count override (preferred over the on-disk counter)
#
# Marker file:
#   $MP_HOME/learn/.session-nudged-<session-id>
#     touched once per session; presence prevents a second nudge in the same
#     session.
#   $MP_HOME/learn/.tool-count-<session-id>
#     decimal integer; incremented on each invocation when no positional
#     count is supplied. Authored by the hook itself so nothing else has to
#     know about its format.
#
# Exit status:
#   0 — always; the hook is advisory, not gating.

set -u

MP_HOME=${MP_HOME:-$HOME/.melt}
MP_NUDGE_THRESHOLD=${MP_NUDGE_THRESHOLD:-20}

sess=${1:-${MP_SESSION_ID:-}}
[ -n "$sess" ] || sess="ppid-$PPID"
count_override=${2:-}

learn_dir="$MP_HOME/learn"
mkdir -p "$learn_dir" 2>/dev/null || exit 0

count_file="$learn_dir/.tool-count-$sess"
nudge_marker="$learn_dir/.session-nudged-$sess"

# Read or update the on-disk tool-call counter. If the caller passed a count
# positionally we trust it; otherwise we increment by one.
if [ -n "$count_override" ]; then
  count=$count_override
  printf '%s\n' "$count" > "$count_file" 2>/dev/null || :
else
  prev=0
  [ -f "$count_file" ] && prev=$(cat "$count_file" 2>/dev/null || printf 0)
  case "$prev" in
    ''|*[!0-9]*) prev=0 ;;
  esac
  count=$((prev + 1))
  printf '%s\n' "$count" > "$count_file" 2>/dev/null || :
fi

# Threshold not crossed yet — nothing to print.
if [ "$count" -lt "$MP_NUDGE_THRESHOLD" ]; then
  exit 0
fi

# Already nudged in this session — stay silent.
if [ -e "$nudge_marker" ]; then
  exit 0
fi

# Touch the marker FIRST so a re-entrant invocation (some harnesses retry on
# transient failure) can't double-print.
: > "$nudge_marker" 2>/dev/null || :

cat <<NUDGE
Session has accumulated $count tool calls. Before /clear, consider running
mp:learn to harvest any reusable techniques into new or updated skills.
Skip if nothing felt reusable.
NUDGE

exit 0
