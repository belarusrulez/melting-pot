#!/bin/sh
# test/e2e/run-scenarios.sh — drive the P0 agent-loop scenarios through real
# `claude -p` and assert each with oracle.sh. Runs identically on the host and
# inside the Docker image (the only difference is who set CLAUDE_CODE_OAUTH_TOKEN).
#
# Per scenario (plans/e2e-docker-design.md §4):
#   fresh mktemp sandbox -> seed.sh (two overlays) -> claude -p (NO --bare,
#   stream-json) -> oracle.sh (CHOICE + BEHAVIOR + anti-silent-no-op).
#
# Auth: requires CLAUDE_CODE_OAUTH_TOKEN (subscription token) OR ANTHROPIC_API_KEY
#       in the environment. NEVER baked into the image — injected at run time.
#
# Env knobs:
#   REPO        repo root (default: two dirs up from this script)
#   SCENARIOS   scenario table (default: ./scenarios.tsv)
#   ARTIFACTS   where to persist transcripts (default: mktemp)
#   ONLY        space list of scenario ids to run (default: all)
#   TURN_TIMEOUT seconds per claude turn (default 180)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
SCENARIOS=${SCENARIOS:-$HERE/scenarios.tsv}
ARTIFACTS=${ARTIFACTS:-$(mktemp -d)}
TURN_TIMEOUT=${TURN_TIMEOUT:-180}
ONLY=${ONLY:-}
MODEL_DEFAULT=claude-haiku-4-5-20251001

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: no auth in env (set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY)"; exit 3
fi
command -v claude  >/dev/null 2>&1 || { echo "ERROR: claude CLI not found"; exit 3; }
command -v jq      >/dev/null 2>&1 || { echo "ERROR: jq not found"; exit 3; }

echo "artifacts: $ARTIFACTS"
pass=0 fail=0 skip=0 total_cost=0

# read scenarios.tsv (tab-separated); skip comments/blanks
while IFS='	' read -r id model skill substr prompt; do
  case "$id" in ''|\#*) continue ;; esac
  [ -n "$ONLY" ] && ! printf ' %s ' "$ONLY" | grep -q " $id " && continue
  [ -n "$model" ] || model=$MODEL_DEFAULT

  ADIR="$ARTIFACTS/$id"; mkdir -p "$ADIR"        # outputs (may be a bind mount)
  RUN=$(mktemp -d)                               # sandbox: always container/host-local fs
  # seed (in a subshell so its env doesn't leak); capture the env block
  envblock=$(REPO="$REPO" RUN="$RUN" sh "$HERE/seed.sh" 2>"$ADIR/seed.err") || {
    echo "[$id] SEED-FAIL (see $ADIR/seed.err)"; fail=$((fail+1)); continue; }
  eval "$envblock"   # exports HOME/MP_HOME/MP_PATTERNS/CLAUDE_CONFIG_DIR for this scenario

  printf '[%s] running (model=%s)... ' "$id" "$model"
  timeout "$TURN_TIMEOUT" claude -p "$prompt" \
    --model "$model" \
    --output-format stream-json --verbose \
    --allowed-tools "Skill,Bash,Read" \
    --permission-mode bypassPermissions \
    --no-session-persistence \
    < /dev/null > "$ADIR/run.ndjson" 2> "$ADIR/run.err"
  rc=$?
  if [ "$rc" = 124 ]; then echo "TIMEOUT -> SKIP"; skip=$((skip+1)); rm -rf "$RUN"; continue; fi

  sh "$HERE/oracle.sh" "$ADIR/run.ndjson" "$skill" "$substr" "$MP_HOME"
  orc=$?
  rm -rf "$RUN"   # teardown sandbox; transcript already in $ADIR
  case "$orc" in
    0) pass=$((pass+1)) ;;
    2) skip=$((skip+1)) ;;
    *) fail=$((fail+1)) ;;
  esac
  c=$(tail -1 "$ADIR/run.ndjson" | jq -r '.total_cost_usd // 0' 2>/dev/null)
  total_cost=$(awk "BEGIN{print $total_cost + ${c:-0}}")
done < "$SCENARIOS"

echo "--------------------------------------------------"
printf 'RESULT: %d passed, %d failed, %d skipped  (cost ~$%.4f)\n' "$pass" "$fail" "$skip" "$total_cost"
echo "transcripts in: $ARTIFACTS"
[ "$fail" -eq 0 ]
