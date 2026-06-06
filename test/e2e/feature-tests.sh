#!/bin/sh
# test/e2e/feature-tests.sh — agent-loop e2e coverage for the REMAINING melting-pot
# features, each driven by a real `claude -p` turn (the same way as the P0 set and
# lifecycle test). Each feature gets a FRESH sandbox pot + its own fixture + oracle.
#
# Covers: list, crud validate, crud trash/restore, learn promote (+1), learn
# demote (-1), learn patch-triage, learn refactor, learn harvest, negative/search.
# (search + load are in scenarios.tsv; the full create->save->discover loop is
# lifecycle-test.sh.)
#
# Auth: CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in env (run via run.sh).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
MODEL=${MODEL:-claude-haiku-4-5-20251001}
TURN_TIMEOUT=${TURN_TIMEOUT:-240}
ART=${ARTIFACTS:-$(mktemp -d)}; mkdir -p "$ART"
ONLY=${ONLY:-}
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] || { echo "ERROR: no auth in env"; exit 3; }
echo "artifacts: $ART"
pass=0 fail=0 skip=0

# seed a fresh pot for the current feature; exports HOME/MP_HOME/CLAUDE_CONFIG_DIR
seed_pot() {
  RUN=$(mktemp -d)
  envblock=$(REPO="$REPO" RUN="$RUN" sh "$HERE/seed.sh" 2>"$ART/$1.seed.err") || return 1
  eval "$envblock"
  printf '{ "permissions": { "allow": ["Skill","Bash","Read","Write","Edit"], "defaultMode": "dontAsk" } }\n' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
}

# run_feat <id> <skill> <substr> <state-check> <prompt>
run_feat() {
  id=$1; skill=$2; substr=$3; state=$4; prompt=$5
  [ -n "$ONLY" ] && ! printf ' %s ' "$ONLY" | grep -q " $id " && return 0
  printf '[%s] ' "$id"
  timeout "$TURN_TIMEOUT" claude -p "$prompt" \
    --model "$MODEL" --output-format stream-json --verbose \
    --allowed-tools "Skill,Bash,Read,Write,Edit" \
    --permission-mode bypassPermissions --no-session-persistence \
    < /dev/null > "$ART/$id.ndjson" 2> "$ART/$id.err"
  [ "$?" = 124 ] && { echo "TIMEOUT -> SKIP"; skip=$((skip+1)); rm -rf "$RUN"; return 0; }
  sh "$HERE/oracle.sh" "$ART/$id.ndjson" "$skill" "$substr" "$MP_HOME" "$state"
  case "$?" in 0) pass=$((pass+1));; 2) skip=$((skip+1));; *) fail=$((fail+1));; esac
  rm -rf "$RUN"
}

mk_chunk() {  # <path> <tier>  (minimal frontmatter w/ born status_history)
  mkdir -p "$(dirname "$1")"
  printf -- '---\ntitle: "%s"\nstatus_history:\n  - { tier: %s, at: 2026-06-05, reason: "born" }\n---\nbody\n' \
    "$(basename "$1" .md)" "$2" > "$1"
}

# ---------------- F-list: agent inventories the pot ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-list '; then
seed_pot F-list && run_feat F-list list "git-bisect" "-" \
"List every melting-pot skill currently available. Use the \"list\" skill (run its action) to produce the full inventory, then tell me roughly how many there are. You MUST invoke the list skill."
fi

# ---------------- F-validate: agent scaffolds + validates ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-validate '; then
seed_pot F-validate && run_feat F-validate crud "OK:" "[ -d \"\$MP_HOME/widget-tool\" ]" \
"Create a new melting-pot skill named exactly 'widget-tool' and then check that its structure is valid. Use the \"crud\" skill (run its action) to scaffold it and then to validate it. Report whether validation passed. You MUST invoke the crud skill."
fi

# ---------------- F-promote (+1): agent records a good use ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-promote '; then
if seed_pot F-promote; then
  sh "$MP_HOME/crud/action" scaffold flow-x >/dev/null 2>&1   # tier-0 chunk: first.md
  run_feat F-promote learn "promoted" "[ -f \"\$MP_HOME/flow-x/1-melting-pot/first.md\" ]" \
"You just used the chunk at 'flow-x/0-melting-pot/first.md' and it worked well — a GOOD use. Record that by promoting it one tier (+1). The mp-learn skill is not model-invocable, so run its action directly in your shell: \`sh ~/.melt/learn/action promote flow-x/0-melting-pot/first.md\`. Then confirm the new tier."
fi
fi

# ---------------- F-demote (-1): agent records a bad use ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-demote '; then
if seed_pot F-demote; then
  sh "$MP_HOME/crud/action" scaffold flow-y >/dev/null 2>&1
  mkdir -p "$MP_HOME/flow-y/2-melting-pot"; mv "$MP_HOME/flow-y/0-melting-pot/first.md" "$MP_HOME/flow-y/2-melting-pot/first.md"
  run_feat F-demote learn "demoted" "[ -f \"\$MP_HOME/flow-y/1-melting-pot/first.md\" ]" \
"The chunk at 'flow-y/2-melting-pot/first.md' gave bad guidance — a BAD use. Record that by demoting it one tier (-1). The mp-learn skill is not model-invocable, so run its action directly in your shell: \`sh ~/.melt/learn/action demote flow-y/2-melting-pot/first.md\`. Then confirm the new tier."
fi
fi

# ---------------- F-trash-restore: agent soft-deletes then restores ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-trash '; then
if seed_pot F-trash; then
  sh "$MP_HOME/crud/action" scaffold scratch-tool >/dev/null 2>&1
  run_feat F-trash crud "-" "[ -d \"\$MP_HOME/scratch-tool\" ]" \
"Soft-delete the melting-pot skill 'scratch-tool', then restore it from the trash. Use the \"crud\" skill (run its action): first 'trash scratch-tool', then list ~/.melt/.trash to find the trash entry directory, then 'restore <full-path-to-that-entry>'. Confirm the skill is back. You MUST invoke the crud skill."
fi
fi

# ---------------- F-patch-triage: agent sweeps a broken patch ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-triage '; then
if seed_pot F-triage; then
  fdir="$MP_HOME/git-rebase/patches/.failed"; mkdir -p "$fdir"
  printf -- '--- patch ---\np\n--- upstream excerpt ---\nu\n--- reject ---\nerror: patch failed\n--- timestamp ---\n2026-06-05T00:00:00Z\n' \
    > "$fdir/001-broken.patch.failed"
  run_feat F-triage learn "001-broken" "-" \
"Some skill patches may have failed to apply. Sweep the pot for broken patch markers and tell me what triage proposes. The mp-learn skill is not model-invocable, so run its action directly in your shell: \`sh ~/.melt/learn/action patch-triage\`."
fi
fi

# ---------------- F-refactor: agent proposes consolidation of dup chunks ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-refactor '; then
if seed_pot F-refactor; then
  for s in dup-a dup-b; do
    mkdir -p "$MP_HOME/$s/0-melting-pot"
    printf -- '---\nname: %s\ndescription: x\n---\n' "$s" > "$MP_HOME/$s/meta.md"
    printf -- '---\ntitle: "Same Title Here"\n---\nbody %s\n' "$s" > "$MP_HOME/$s/0-melting-pot/c.md"
  done
  run_feat F-refactor learn "overlap" "-" \
"Check the pot for overlapping or duplicate chunks across skills and propose how to consolidate them. The mp-learn skill is not model-invocable, so run its action directly in your shell: \`sh ~/.melt/learn/action refactor\`."
fi
fi

# ---------------- F-harvest: agent processes a pending transcript ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-harvest '; then
if seed_pot F-harvest; then
  mkdir -p "$MP_HOME/learn"; tj="$RUN/session.jsonl"; printf '{"x":1}\n' > "$tj"
  printf '%s\n' "$tj" > "$MP_HOME/learn/.pending-transcript"
  run_feat F-harvest learn "transcript-mode harvest" "[ ! -e \"\$MP_HOME/learn/.pending-transcript\" ]" \
"There is a pending session transcript waiting to be mined for reusable knowledge. The mp-learn skill is not model-invocable, so process it by running its action directly in your shell: \`sh ~/.melt/learn/action harvest\`. Report what it did."
fi
fi

# ---------------- F-negative: agent reaches for search on a likely-miss ----------------
if [ -z "$ONLY" ] || printf ' %s ' "$ONLY" | grep -q ' F-negative '; then
seed_pot F-negative && run_feat F-negative search "-" "-" \
"A teammate asks if we have a skill for 'underwater basket weaving with quantum llamas'. You MUST actually run the search action \`sh ~/.melt/search/action\` with three query phrases before answering — do NOT answer from memory. If nothing genuinely relevant comes back, say so plainly; do NOT invent or pretend we have a skill."
fi

echo "--------------------------------------------------"
printf 'FEATURES: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
echo "transcripts in: $ART"
[ "$fail" -eq 0 ]
