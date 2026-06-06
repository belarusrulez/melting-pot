#!/bin/sh
# test/e2e/lifecycle-test.sh — the full melting-pot value loop, end to end,
# across TWO separate real `claude -p` sessions sharing ONE persistent pot:
#
#   1. CREATE  — we stand up new infra (Acme Edge deploy via `acmectl`).
#   2. SAVE    — session 1: a real agent harvests it into the pot (crud scaffold
#                + writes the tier-0 chunk). This is "the bot discovers + saves it".
#   3. DISCOVER— session 2 (a DIFFERENT, fresh session with NO shared context)
#                searches the pot and finds the skill session 1 saved.
#
# The proof that matters: session 2 knows nothing from session 1's conversation
# (separate invocation, --no-session-persistence, distinct session_id). The only
# way it can surface the skill is because the knowledge PERSISTED IN THE POT.
#
# Auth: CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in env (run via run.sh).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
MODEL=${MODEL:-claude-haiku-4-5-20251001}
TURN_TIMEOUT=${TURN_TIMEOUT:-240}
ART=${ARTIFACTS:-$(mktemp -d)}; mkdir -p "$ART"
SKILL_NAME=acme-edge-deploy

[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] || { echo "ERROR: no auth in env"; exit 3; }
echo "artifacts: $ART"

# ---- seed ONE pot, shared by both sessions (do NOT reseed between them) ----
RUN=$(mktemp -d)
envblock=$(REPO="$REPO" RUN="$RUN" sh "$HERE/seed.sh" 2>"$ART/seed.err") || { echo "SEED-FAIL"; cat "$ART/seed.err"; exit 1; }
eval "$envblock"
# session 1 needs Write/Edit so the agent can author the chunk body
printf '{ "permissions": { "allow": ["Skill","Bash","Read","Write","Edit"], "defaultMode": "dontAsk" } }\n' \
  > "$CLAUDE_CONFIG_DIR/settings.json"

run_turn() {  # <prompt> <outfile> <allowed-tools>
  timeout "$TURN_TIMEOUT" claude -p "$1" \
    --model "$MODEL" --output-format stream-json --verbose \
    --allowed-tools "$3" --permission-mode bypassPermissions --no-session-persistence \
    < /dev/null > "$2" 2> "${2%.ndjson}.err"
}
sid() { head -1 "$1" | jq -r '.session_id // empty' 2>/dev/null; }

fails=0

# ============================== SESSION 1: SAVE ==============================
echo "--- session 1: agent harvests new infra into the pot ---"
P1="We just built new internal infra: deploying a service to the Acme Edge CDN. \
The procedure is: run \`acmectl push --region edge1 --token \$ACME_TOKEN\`, then \
verify with \`acmectl status edge1\`. Save this as a REUSABLE melting-pot skill so \
future sessions can find it. Use the \"crud\" skill (run its action) to scaffold a \
NATIVE skill named exactly '${SKILL_NAME}'. Then write the deploy steps into its \
tier-0 chunk file (0-melting-pot/first.md) and set the skill's meta.md description \
to clearly mention deploying / rolling out to the Acme Edge CDN with acmectl. You \
MUST invoke the crud skill."
run_turn "$P1" "$ART/s1.ndjson" "Skill,Bash,Read,Write,Edit"

# oracle 1: crud chosen+fired, is_error false, AND the skill now exists in the pot
sh "$HERE/oracle.sh" "$ART/s1.ndjson" crud "-" "$MP_HOME" \
  "[ -d '$MP_HOME/$SKILL_NAME' ] && ls '$MP_HOME/$SKILL_NAME'/0-melting-pot/*.md >/dev/null 2>&1" \
  && echo "  SESSION1 PASS: bot saved skill into the pot" || { echo "  SESSION1 FAIL"; fails=$((fails+1)); }

# the pot persists across sessions; refresh the index (auto-reindex also covers this)
sh "$MP_HOME/search/action" reindex >"$ART/reindex.log" 2>&1

# ============================ SESSION 2: DISCOVER ===========================
echo "--- session 2: a FRESH session discovers it via search ---"
P2="A teammate asks how to deploy our service to the Acme Edge CDN. You have no \
prior context. Use the \"search\" skill (run its action) to find whether we already \
have a melting-pot skill covering Acme Edge deployment, then report the skill name \
it returns. You MUST invoke the search skill."
run_turn "$P2" "$ART/s2.ndjson" "Skill,Bash,Read"

# oracle 2: search chosen+fired, and the result surfaced the skill session 1 saved
sh "$HERE/oracle.sh" "$ART/s2.ndjson" search "$SKILL_NAME" "$MP_HOME" \
  && echo "  SESSION2 PASS: fresh session found the saved skill in the pot" || { echo "  SESSION2 FAIL"; fails=$((fails+1)); }

# ---- prove the two sessions are genuinely distinct (no carried-over context) ----
s1=$(sid "$ART/s1.ndjson"); s2=$(sid "$ART/s2.ndjson")
if [ -n "$s1" ] && [ -n "$s2" ] && [ "$s1" != "$s2" ]; then
  echo "  ISOLATION PASS: distinct session ids ($s1 != $s2) — discovery came from the pot, not memory"
else
  echo "  ISOLATION FAIL: session ids '$s1' / '$s2'"; fails=$((fails+1))
fi

rm -rf "$RUN"
echo "--------------------------------------------------"
if [ "$fails" -eq 0 ]; then
  echo "LIFECYCLE PASS: create -> bot saved -> new session discovered (full loop)"; exit 0
else
  echo "LIFECYCLE FAIL: $fails stage(s) failed (see $ART)"; exit 1
fi
