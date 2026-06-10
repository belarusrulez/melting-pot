# REGISTER-HOOKS.md — melting-pot hook manifest

> Emitted by `install/install.sh`. The calling LLM reads this file and
> translates each row below into whatever the active harness needs.
>
> **This file is the source of truth.** The installer does NOT mutate
> harness config (Q-003). Translation responsibilities live with the
> calling LLM.
>
> NOTE: this committed copy uses `~/.melt/...` placeholders. When you run
> `install/install.sh`, a *sandbox-accurate* version of this manifest is
> also written to `$MP_HOME/REGISTER-HOOKS.md` with absolute script paths
> baked in. Read either: same shape, different paths.

## What the calling LLM should do

For each row in **Hooks** below:

1. Read the **Script** path and **Hook event** slot.
2. Register the script in the active harness's config so it fires on that
   event. Examples by harness:
   - **Claude Code:** append an entry to `hooks.<event>` in
     `~/.claude/settings.json`. (Use the `update-config` skill if
     available, or hand-edit.)
   - **Cursor:** add a rule in `.cursorrules` that runs the script at
     the equivalent moment.
   - **Codex / others:** consult that harness's hook docs.

Verify each registration by triggering the corresponding event once and
confirming the script's stdout reaches the agent.

## Hooks

| Script | Hook event | Purpose | Install-target hint |
| --- | --- | --- | --- |
| `~/.melt/hooks/melt-nudge.sh` | `Stop` | After each assistant turn ends, nudges the agent (once per session, after 20 tool calls — `MP_NUDGE_THRESHOLD` env overrides) to run `mp-learn` before `/clear`. Plain-text stdout; harness-agnostic. | Claude Code: add to `hooks.Stop` in `~/.claude/settings.json`. |
| `~/.melt/hooks/melt-resume.sh` | `SessionStart:clear` | When a session is cleared, writes the prior transcript path to `$MP_HOME/learn/.pending-transcript` and emits a resume-or-harvest prompt. `mp-learn harvest --transcript` consumes the handshake via read-then-unlink. | Claude Code: add to `hooks.SessionStart` with matcher `clear` in `~/.claude/settings.json`. |

## Sanity checklist for the calling LLM

- [ ] Both hook scripts are executable (`chmod +x` already applied by the
      installer; re-check if you copied them elsewhere).
- [ ] Their absolute paths are reachable from the harness (no `~` in the
      registration unless the harness expands it).
- [ ] The harness fires the matching event when expected (see harness docs).

## When to re-emit this manifest

Run `install.sh --emit-manifest-only` after:

- Changing `$MP_HOME` (script paths in the table will refresh).
- Upgrading melting-pot to a new version that ships additional hooks.

The script is idempotent; re-running is safe.
