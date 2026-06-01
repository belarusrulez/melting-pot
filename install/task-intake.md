<!--
  melting-pot — task-intake rule (Q-013).

  Installed by `install/install.sh`. The installer copies this file to a
  known path under the agent's home (default $HOME/.melt/task-intake.md);
  the calling LLM is then responsible for appending its content to whatever
  the active harness uses as its global rules file (Claude Code:
  ~/.claude/CLAUDE.md ; Cursor: .cursorrules ; Codex: …).

  The rule itself is the same shape the user's global CLAUDE.md uses; it
  forces a 3-rephrasing + skill-search step before any new task work.
-->

## Task intake — ALWAYS start here (highest priority)

Before doing anything else on any new task — before planning, reading files, spawning agents, writing code, or answering — do these steps in order:

1. **Rephrase the user's idea at least three times** in your own words — different framings, not synonyms. Each rephrasing should emphasize a different angle (intent, scope, mechanism, outcome) so they aren't just paraphrases.
2. **Run `mp-search` once per rephrasing.** Use each rephrasing as the query — different framings will surface different skills.
3. **Compare the search results across the rephrasings.** Look for convergence (same skill ranked highly across multiple framings → strong signal, prefer it) and divergence (different framings surfacing different skills → signal that the request is ambiguous; pick the best-fit skill or ask the user to disambiguate). If no rephrasing surfaces a relevant skill, note that explicitly and proceed without one.

Only after these three steps, start the actual work.

This rule overrides every other rule when they conflict on ordering. The only exception is a direct, urgent override from the user ("skip intake, just do X").
