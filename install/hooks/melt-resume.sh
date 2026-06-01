#!/bin/sh
# melt-resume.sh — SessionStart:clear-event hook for melting-pot.
#
# Harness-agnostic POSIX sh. When the harness clears a session, this script
# writes the prior transcript's path to a handshake file the next session's
# `mp-learn harvest --transcript` consumer reads (and unlinks) on demand.
#
# Per Q-003: makes NO Claude-Code-specific JSON assumptions. The installer's
# REGISTER-HOOKS.md tells the calling agent which harness slot to bind this
# to (e.g. Claude Code: `hooks.SessionStart` with the `clear` matcher).
#
# Inputs (environment):
#   MP_HOME             — overlay root (default: ~/.melt)
#   MP_PRIOR_TRANSCRIPT — path to the prior session's transcript .jsonl
#   MP_PRIOR_SESSION_ID — prior session uuid (optional, surfaced in prompt)
#
# Inputs (positional, optional):
#   $1 — transcript path override (preferred over env)
#   $2 — prior session id override (preferred over env)
#
# Handshake file:
#   $MP_HOME/learn/.pending-transcript
#     plain-text, contains the absolute transcript path. Written atomically
#     via tmp-then-rename so a half-written read can't fire stray triggers.
#     `mp-learn harvest --transcript` consumes via read-then-unlink.
#
# Exit status:
#   0 — always; the hook is advisory, not gating.

set -u

MP_HOME=${MP_HOME:-$HOME/.melt}

transcript=${1:-${MP_PRIOR_TRANSCRIPT:-}}
prior_uuid=${2:-${MP_PRIOR_SESSION_ID:-}}

learn_dir="$MP_HOME/learn"
mkdir -p "$learn_dir" 2>/dev/null || exit 0

pending="$learn_dir/.pending-transcript"

# Write the handshake atomically when we have a transcript path. If we don't
# (e.g. fresh harness install, no prior session), skip the write but still
# emit a useful prompt.
if [ -n "$transcript" ]; then
  tmp="$pending.tmp.$$"
  if printf '%s\n' "$transcript" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$pending" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
fi

# Print the resume-or-harvest prompt the next session reads. Plain text — the
# calling agent decides what to do with it (Claude Code injects it into the
# session, Cursor surfaces it as a notification, etc.).
if [ -n "$transcript" ]; then
  cat <<PROMPT
Cleared.${prior_uuid:+ Resume prior session with:
  claude --resume $prior_uuid
}
The prior session's transcript is saved at:
  $transcript

Run \`mp-learn\` against that transcript? Type \`yes\` as your next
message to harvest reusable techniques into new or updated skills.
Anything else (or just start your next task) skips harvesting.
PROMPT
else
  cat <<PROMPT
Cleared. No prior transcript path was supplied to melt-resume.sh, so
\`mp-learn harvest --transcript\` is unavailable. \`mp-learn harvest\`
will fall back to live-context proposals via stdin if you invoke it.
PROMPT
fi

exit 0
