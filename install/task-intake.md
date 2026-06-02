<!--
  melting-pot — task-intake rule (Q-013).

  Installed by `install/install.sh`. The installer copies this file to a
  known path under the agent's home (default $HOME/.melt/task-intake.md);
  the calling LLM is then responsible for appending its content to whatever
  the active harness uses as its global rules file (Claude Code:
  ~/.claude/CLAUDE.md ; Cursor: .cursorrules ; Codex: …).

  The rule defines one reusable loop with a clear split of labor:
  the MAIN agent decomposes the request and later compiles the results;
  a SUBAGENT finds the right skill for each subtask in isolated context.
  Run it before any new task AND re-enter it any time the agent is stuck.
  It forces skill-search to drive the work, not just gate it.
-->

## Task intake — ALWAYS start here (highest priority)

There is one **reusable intake loop** with three roles. The **main agent** owns the ends (split the work, then assemble the answer); a **subagent** owns the expensive middle (find the right skill per subtask in isolated context, so the main thread never ingests search digests or skill bodies). Run it before starting any new task, and re-enter it any time you get stuck (see *When to run* below).

1. **Decompose — main agent.** Split the request into the smallest independent subtasks — one goal each. A simple request is a single subtask; a compound request ("do X, then Y, and also Z") becomes several. This stays in the main thread: it's cheap, and the main agent needs the full shape of the work to compile later.

2. **Find the right skill per subtask — one subagent each.** For every subtask, spawn a subagent (any harness's sub-agent / isolated-context primitive) and fan them out in parallel where the subtasks are independent. Each subagent, for its one subtask:
   - **Rephrase ×3** — restate the subtask three ways, different angles, not synonyms (intent, scope, mechanism, outcome);
   - runs `mp-search` with the three axes (literal phrase / synonym-jargon / intent-goal — the rephrasings map onto these);
   - reads candidate manifests and triages, **comparing convergence** (same skill ranked highly under multiple axes → prefer it) vs **divergence** (different axes → ambiguous; pick best-fit or flag it); `mp-load`s only the one it commits to;
   - returns **only** a compact result to the main thread: the chosen skill **name + path**, a **distilled** ready-to-execute summary of its instructions, and a one-line why — or, if nothing fits after up to 3 candidates, that fact plus what was tried.

   The heavy reading lives and dies in the subagent. Skip the subagent only for a trivial single lookup (one obvious skill, tiny body, no triage).

3. **Compile into one picture — main agent.** Collect the subagents' distilled results and merge them into a single coherent plan: order dependencies, reconcile overlaps where two subtasks picked related skills, and note any gaps where no skill fit. Only then start the actual work — loading a full skill body into the main thread only when you must execute steps the subagent couldn't (e.g. edits in the user's working tree).

   **When you wrap up, report use (close the loop).** For any skill whose **overlay chunk** (`<skill>/N-melting-pot/…`) materially helped, `sh ~/.melt/learn/action promote <chunk>`; if a chunk misled you, `demote` it. This is the only thing that moves the tier gradient — skipping it leaves harvested knowledge stuck at tier 0. Nothing to do for pure registered skills with no overlay chunks.

### When to run the loop

- **At intake** — before planning, reading files, spawning agents, writing code, or answering, for every new task.
- **Whenever you're lost** — mid-task, any time you're stuck, uncertain how to proceed, facing an unfamiliar domain, or about to improvise/guess: treat the sticking point as a fresh subtask, spawn a skill-finding subagent for it, and compile its result back in before continuing. The pot is a standing fallback, not a one-time gate — reach for it as often as you need.

This rule overrides every other rule when they conflict on ordering. The only exception is a direct, urgent override from the user ("skip intake, just do X").
