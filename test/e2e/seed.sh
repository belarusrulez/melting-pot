#!/bin/sh
# test/e2e/seed.sh — seed ONE scenario-private sandbox (plans/e2e-docker-design.md §3).
#
# Builds the two overlays into $RUN:
#   (A) $CLAUDE_CONFIG_DIR/skills/<skill> symlinks + settings.json  -> Skill tool SEES mp skills
#   (B) ~/.melt (= $MP_HOME) via the real install.sh + corpus + reindex -> Bash RUNS the actions
#
# Caller exports REPO and RUN, and (after seeding) sets HOME=$RUN so the
# skills' "~/.melt/..." instructions resolve into the sandbox.
#
# Usage:  REPO=<repo> RUN=<dir> sh seed.sh   (prints the env block to eval)
set -eu
REPO=${REPO:?repo root}
RUN=${RUN:?run dir}
CORPUS=${CORPUS:-$REPO/test/skills}

export HOME="$RUN"
export MP_HOME="$RUN/.melt"
export MP_PATTERNS="$RUN/.melt/repos.patterns"
export CLAUDE_CONFIG_DIR="$RUN/cfg"

# (B) runtime overlay via the real installer (asserts Q-003; exit 4 = breach)
sh "$REPO/install/install.sh" >"$RUN/install.log" 2>&1
printf '%s\t*\n' "$CORPUS" > "$MP_PATTERNS"
sh "$MP_HOME/search/action" reindex >"$RUN/reindex.log" 2>&1

# (A) registration overlay: make the Skill tool see each mp/<skill>/
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
for d in "$REPO"/mp/*/; do
  s=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  ln -sf "$d" "$CLAUDE_CONFIG_DIR/skills/$s"
done
printf '{ "permissions": { "allow": ["Skill","Bash","Read","Write"], "defaultMode": "dontAsk" } }\n' \
  > "$CLAUDE_CONFIG_DIR/settings.json"

# emit the env so the runner can eval it
echo "export HOME='$HOME' MP_HOME='$MP_HOME' MP_PATTERNS='$MP_PATTERNS' CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR'"
