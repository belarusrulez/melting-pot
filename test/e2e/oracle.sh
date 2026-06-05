#!/bin/sh
# test/e2e/oracle.sh — assertion oracle for one agent-loop scenario transcript.
#
# Implements the two-tier oracle from plans/e2e-test-plan.md §3:
#   CHOICE   — agent chose + fired the skill (the non-deterministic part).
#   BEHAVIOR — exit/is_error + tool_result substring + (optional) FS state.
# Pass requires BOTH. A zero-tool-call run is a HARD FAIL by construction
# (ANTI-SILENT-NO-OP INVARIANT, §2a) — there is no free-text path to green.
#
# Usage:
#   sh oracle.sh <ndjson> <expected_skill> <expect_substr> [mp_home] [state_check]
#     <ndjson>          path to stream-json transcript (one JSON object per line)
#     <expected_skill>  bare dirname the agent must fire, e.g. "search" (never "mp-search")
#     <expect_substr>   substring that MUST appear in the matching tool_result
#                       (e.g. a skill slug "git-bisect", or "axes=3"); "-" to skip
#     [mp_home]          optional; reserved for FS-state scenarios
#     [state_check]      optional shell snippet; non-zero exit => BEHAVIOR fail
#
# Exit: 0 pass · 1 assertion fail · 2 transient (API down / timeout => caller SKIPs)
set -u
ND=${1:?ndjson path}; SKILL=${2:?expected skill}; SUB=${3:-"-"}
MP_HOME=${4:-}; STATE=${5:-}

fail() { echo "FAIL: $1"; exit 1; }
[ -s "$ND" ] || fail "empty transcript $ND"

final=$(tail -n 200 "$ND" | grep '"type":"result"' | tail -1)
[ -n "$final" ] || fail "no result event (truncated run?)"

# --- transient class -> SKIP (exit 2): API unreachable / overloaded / rate-limited
errstatus=$(printf '%s' "$final" | jq -r '.api_error_status // empty' 2>/dev/null)
case "$errstatus" in
  429|500|502|503|504|529) echo "SKIP: transient api_error_status=$errstatus"; exit 2 ;;
esac

# --- BEHAVIOR 1: never trust $? — read is_error from JSON (§2 gotcha)
is_error=$(printf '%s' "$final" | jq -r '.is_error' 2>/dev/null)
if [ "$is_error" != "false" ]; then
  msg=$(printf '%s' "$final" | jq -r '.result // ""' 2>/dev/null | head -c 120)
  case "$msg" in
    *"Not logged in"*) fail "auth: $msg (token not injected)";;
    *) fail "is_error=$is_error: $msg";;
  esac
fi
# permission_denials must be empty
den=$(printf '%s' "$final" | jq -r '(.permission_denials // []) | length' 2>/dev/null)
[ "${den:-0}" = "0" ] || fail "permission_denials=$den (allowlist too tight)"

# --- CHOICE: Skill(skill==SKILL) chosen AND Bash ran the matching action
chose=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' "$ND" 2>/dev/null | grep -c "\"$SKILL\"")
[ "${chose:-0}" -ge 1 ] || fail "ANTI-SILENT-NO-OP: agent never fired Skill(skill:\"$SKILL\")"
fired=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' "$ND" 2>/dev/null | grep -c "$SKILL/action")
[ "${fired:-0}" -ge 1 ] || fail "agent chose Skill but never ran sh .../$SKILL/action via Bash"

# --- BEHAVIOR 2: matching tool_result carried the expected substring
if [ "$SUB" != "-" ]; then
  hit=$(jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result") | (.content // "" | if type=="array" then map(.text // "")|join(" ") else tostring end)' "$ND" 2>/dev/null | grep -c -- "$SUB")
  [ "${hit:-0}" -ge 1 ] || fail "expected substring '$SUB' not found in any tool_result"
fi

# --- BEHAVIOR 3 (optional): filesystem state mutation
if [ -n "$STATE" ]; then
  ( eval "$STATE" ) || fail "state check failed: $STATE"
fi

cost=$(printf '%s' "$final" | jq -r '.total_cost_usd // 0' 2>/dev/null)
turns=$(printf '%s' "$final" | jq -r '.num_turns // 0' 2>/dev/null)
echo "PASS: chose+fired Skill($SKILL), result ok (turns=$turns cost=\$$cost)"
exit 0
