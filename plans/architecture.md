# melting-pot — architecture

> Vendor-neutral, file-based skill store. Five meta-skills + overlay + git-patches + two harness-agnostic hooks. POSIX sh + SQLite FTS5 + RRF.

This file is the single source of truth for **what connects to what**. Component status is tracked in `build_order.md`; open questions in `open_questions.md`.

## Hub diagram

```mermaid
graph TD
  %% ── User-facing meta-skills (the five "mp:*") ─────────────────────────────
  subgraph SKILLS["meta-skills (mp/*)"]
    SEARCH["mp:search<br/>3-axis RRF over patched+overlay content"]:::skill
    LOAD["mp:load<br/>compose manifest+chunks+patches → markdown/json"]:::skill
    LIST["mp:list<br/>flat inventory across registered + overlay"]:::skill
    CRUD["mp:crud<br/>scaffold / validate / trash / restore / patch ops"]:::skill
    LEARN["mp:learn<br/>promote / demote / refactor / cascade / harvest / patch-triage"]:::skill
  end

  %% ── Shared library (sourced by every action) ──────────────────────────────
  LIB["mp/lib/discover.sh<br/>discover_skills · fm_field · body_after_fm<br/>parse_patterns · expand_root · sql_esc · json_esc<br/>symlink upstream N-melting-pot/ into overlay"]:::lib
  TIERLIB["mp/lib/tier.sh<br/>walk 0..5-melting-pot dirs · resolve_chunk_path<br/>append status_history · detect full-overlay-mode"]:::lib
  PATCHLIB["mp/lib/patch.sh<br/>list_patches · apply_in_memory · validate_patch<br/>record_failed_patch (→ .failed/)"]:::lib
  COMPOSE["mp/lib/compose.sh<br/>compose_skill (manifest + chunks + patches → markdown/json)"]:::lib

  %% ── Storage layers ────────────────────────────────────────────────────────
  subgraph STORAGE["storage"]
    PATTERNS["~/.melt/repos.patterns<br/>sole config path (clean fork from ~/.sc/)"]:::data
    OVERLAY["~/.melt/&lt;skill&gt;/<br/>user chunks 0..5-melting-pot/<br/>· patches/*.patch · patches/.failed/<br/>· meta.md · symlinks to upstream tier dirs"]:::data
    REGISTERED["registered repos<br/>SKILL.md (treated as tier 5)<br/>and/or N-melting-pot/ subdirs"]:::data
    INDEX["~/.melt/search/index.db<br/>SQLite FTS5 (patched content indexed)"]:::data
    INDEX_HASH["~/.melt/search/.index_hash<br/>SHA-256(skills+chunks+patches+symlinks) — drift detection"]:::data
    TRASH["~/.melt/trash/<br/>soft-deleted skills + .melt-trash-meta.json"]:::data
    PENDING["~/.melt/learn/.pending-transcript<br/>SessionStart:clear → mp:learn handshake"]:::data
    FAILED["~/.melt/&lt;skill&gt;/patches/.failed/<br/>per-failure marker files (LLM-triaged by mp:learn)"]:::data
  end

  %% ── Hooks (POSIX sh, harness-agnostic — installer emits manifest) ────────
  subgraph HOOKS["hooks (harness-agnostic POSIX sh)"]
    NUDGE["install/hooks/melt-nudge.sh<br/>Stop-event nudge after N tool calls<br/>(emits plain stdout — harness-agnostic)"]:::hook
    RESUME["install/hooks/melt-resume.sh<br/>SessionStart:clear event<br/>(emits plain stdout — harness-agnostic)"]:::hook
  end

  %% ── Installer (no longer mutates harness config) ─────────────────────────
  INSTALLER["install/install.sh<br/>seed ~/.melt/, copy hooks, emit manifest<br/>(NEVER mutates ~/.claude/settings.json)"]:::install
  MANIFEST["install/REGISTER-HOOKS.md<br/>(structured markdown tables — sole manifest)<br/>harness-agnostic instruction:<br/>'register these scripts at these event slots'"]:::install
  RULE["install/task-intake.md<br/>global-rule text block — installer emits<br/>same harness-agnostic way for agent to install"]:::install

  %% ── Calling agent (LLM) — translates manifest into harness config ────────
  AGENT["calling agent (LLM)<br/>reads manifest → writes correct harness config<br/>(Claude Code: ~/.claude/settings.json;<br/>Cursor: .cursorrules; etc.)"]:::agent

  %% ── Edges: skills → libraries ─────────────────────────────────────────────
  SEARCH --> LIB
  SEARCH --> PATCHLIB
  SEARCH --> TIERLIB
  LOAD --> LIB
  LOAD --> TIERLIB
  LOAD --> PATCHLIB
  LOAD --> COMPOSE
  LIST --> LIB
  LIST --> TIERLIB
  CRUD --> LIB
  CRUD --> PATCHLIB
  LEARN --> LIB
  LEARN --> TIERLIB
  LEARN -.reads markers.-> FAILED
  PATCHLIB -.writes markers.-> FAILED

  %% ── Edges: skills → storage ───────────────────────────────────────────────
  SEARCH --> INDEX
  SEARCH --> INDEX_HASH
  SEARCH --> PATTERNS
  SEARCH --> OVERLAY
  SEARCH --> REGISTERED
  LOAD --> OVERLAY
  LOAD --> REGISTERED
  LIST --> PATTERNS
  LIST --> OVERLAY
  LIST --> REGISTERED
  CRUD --> OVERLAY
  CRUD --> TRASH
  CRUD --> REGISTERED
  LEARN --> OVERLAY
  LEARN --> PENDING

  %% ── Discover.sh: symlinks upstream tier dirs into overlay ────────────────
  LIB -.symlinks upstream<br/>N-melting-pot/ →<br/>~/.melt/&lt;skill&gt;/N-melting-pot/.-> OVERLAY

  %% ── Edges: installer → everything ─────────────────────────────────────────
  INSTALLER --> PATTERNS
  INSTALLER --> NUDGE
  INSTALLER --> RESUME
  INSTALLER --> MANIFEST
  INSTALLER --> RULE
  MANIFEST -.read by.-> AGENT
  RULE -.read by.-> AGENT
  AGENT -.writes harness-specific config<br/>(settings.json / .cursorrules / …).-> NUDGE
  AGENT -.writes harness-specific config.-> RESUME
  AGENT -.appends task-intake to<br/>harness global rules.-> SEARCH

  %% ── Styles ────────────────────────────────────────────────────────────────
  classDef skill fill:#fde68a,stroke:#92400e,color:#111;
  classDef lib fill:#bfdbfe,stroke:#1e40af,color:#111;
  classDef data fill:#e5e7eb,stroke:#374151,color:#111;
  classDef hook fill:#fecaca,stroke:#991b1b,color:#111;
  classDef install fill:#bbf7d0,stroke:#166534,color:#111;
  classDef agent fill:#ddd6fe,stroke:#5b21b6,color:#111;
```

## Component contracts

### mp:search

- **Inputs:** 3 positional queries (literal / synonym / intent), `--limit`, `--format text|tsv|json`.
- **Process:** auto-reindex if drift hash changed → per-axis FTS5 query capped at top-5 → RRF fusion (k=10) → emit Convergence + Single-axis sections.
- **Indexed unit:** one row per **skill** (not per chunk). The row's `content` field is the concatenation of patched-upstream + every overlay chunk (across all `N-melting-pot/` tier dirs), so search hits any tier. Per-row metadata: `name`, `dirname`, `path`, `description`, `origin (reg|ovl|mix)`, `avg_tier`, `hits` (e.g. `[5:2, 3:1, 0:1]`), `patches_applied`, `patches_failed` (count of `.failed/` markers).
- **Side effects:** atomic reindex on hash drift. Does NOT mutate chunk `use_count` in v1 — see Q-004.
- **Exit:** 0=hits, 1=no hits, 2=config, 3=index, 4=patch-apply hard failure (still emits results; `.failed/` markers recorded; flag in stderr).

### mp:load

- **Inputs:** `<skill-name>` (frontmatter `name:` or dirname), `--format markdown|json`, `--tiers 5,3,0`, `--no-patches`, `--with-history`.
- **Process:** resolve skill → walk overlay tier dirs (`0-melting-pot/`..`5-melting-pot/`) AND any registered tier dirs not already symlinked in → apply `~/.melt/<skill>/patches/*.patch` to upstream content in memory (recording any failures to `patches/.failed/`) → compose unified document (tiers 5→0, alphabetical within tier).
- **Output:** one document. Markdown is default; JSON for programmatic consumers.

### mp:list

- **Inputs:** `--format`, `--root`, `--match`, `--names-only`, `--count`.
- **Process:** discover_skills (union of registered + overlay) → one row per skill with `origin`, `tiers_present` (formatted as e.g. `[0,2,5]-melting-pot` or `legacy` for SKILL.md-only skills), `chunk_count`, `patches_count`, `patches_failed_count`.

### mp:crud

Subcommands (deterministic helpers; the procedure in SKILL.md owns judgment):

| Subcommand | Behaviour |
| --- | --- |
| `collision-check <dirname>` | exit 1 if a skill of that basename already exists |
| `scaffold <target-dir>` | write `meta.md` + `0-melting-pot/first.md` (native six-tier) OR `SKILL.md` (legacy, only if `--legacy`); honour name-derivation rule (first `-` → `:`) |
| `validate <skill-dir>` | frontmatter present + non-empty name/desc + tier dirs are named `0-melting-pot`..`5-melting-pot` only + any action/*.sh executable + all `patches/*.patch` parse-able |
| `trash <source-dir>` | soft-delete to `~/.melt/trash/<ts>-<dirname>/` + write `.melt-trash-meta.json` |
| `restore <trash-entry>` | move back to `orig_path` from meta |
| `import-preview <root>` | TSV: path<TAB>name<TAB>description<TAB>tiers<TAB>issues |
| `patch-add <skill-name> <patch-file>` | copy patch into `~/.melt/<skill>/patches/`, renumber to next slot |
| `patch-list <skill-name>` | list patches in apply order, mark `applies` / `failed` / `not-yet-attempted` |
| `patch-validate <skill-name>` | dry-run apply all patches; report per-patch status (does NOT write `.failed/` markers — read-only check) |
| `patch-remove <skill-name> <patch-id>` | remove a single patch (e.g. `003-add-our-prod-example.patch`); also clears matching `.failed/` marker if present |

### mp:learn

Lifecycle scripts. Each writes a new `status_history` entry into the chunk's frontmatter.

Tier movement is usage-driven: a good use promotes, a bad use demotes, and a bad use at tier 0 removes the chunk. No `promote_when`/`demote_when` rules, no time-decay, no scheduled sweep.

| Subcommand | Behaviour |
| --- | --- |
| `promote <chunk-path>` | good use: mv to `<tier+1>-melting-pot/` and append status_history; refuse at tier 5 |
| `demote <chunk-path>` | bad use: mv to `<tier-1>-melting-pot/`; at tier 0, remove the chunk (after cascade-flagging dependents) |
| `refactor` | identify overlapping chunks via FTS5 near-duplicate detection; propose consolidation |
| `cascade <chunk-path>` | walk `depends_on` graph; flag dependents for review when a dep demotes |
| `harvest` | session-end reflection: read transcript or live context, propose new chunks at tier 0 |
| `harvest --transcript <path>` | post-`/clear` mode: read prior `.jsonl`, propose chunks |
| **`patch-triage`** | sweep every `~/.melt/*/patches/.failed/` marker; for each marker, emit a structured proposal to the calling LLM (regenerate / hand-rewrite / delete / defer) with the patch hunk + upstream excerpt + reject output |

Triggered by: session-end (`harvest` + `patch-triage`), explicit gesture (`promote`/`demote`/`refactor`/`patch-triage`).

### Hooks (harness-agnostic)

Both scripts are pure POSIX sh and emit plain text on stdout. They make no assumptions about the harness's hook-event JSON schema — the harness calls them at the right moment, they print a string for the agent to read. The installer never edits harness config; the calling LLM translates the manifest.

- **`melt-nudge.sh`** (intended for the harness's Stop-event slot) — counts tool calls via marker file `~/.melt/learn/.tool-count-<session>`; once over threshold (default 20), emits one nudge string suggesting `mp:learn` before `/clear`. Marker prevents repeat.
- **`melt-resume.sh`** (intended for the harness's SessionStart:clear-equivalent slot) — writes prior session's `.jsonl` path to `~/.melt/learn/.pending-transcript`, emits the resume-or-harvest prompt. `mp:learn harvest --transcript` consumes with read-then-unlink.

### Installer (`install/install.sh`)

Renamed from the original `install-claude-md.sh` since the installer no longer mutates Claude-specific (or any harness-specific) config. New shape:

- Seeds `~/.melt/repos.patterns` (with optional `--copy-from-sc` flag for one-time migration from `~/.sc/repos.patterns`).
- Symlinks every `mp/*/action` into `~/.melt/<skill>/action`.
- Copies hook scripts into a stable location under `~/.melt/hooks/`.
- **Emits a markdown manifest** (`install/REGISTER-HOOKS.md`, per Q-012) describing what the calling LLM should register where. Single artifact, structured markdown tables — one row per hook with `script-path` / `hook-event-slot` / `description` / `install-target-hint` columns. **Does NOT itself write to `~/.claude/settings.json` or any other harness config.** No stdout TSV mode; no JSON variant — markdown is the sole source of truth.
- Same for the task-intake rule: emits `install/task-intake.md` for the agent to append to whatever the harness uses as its global rules file. Bundled in the same installer per Q-013 — no separate `install-rules.sh`.
- `--dry-run` flag on every mutating step.

The calling LLM (the agent running the installer) is the bridge to harness-specific config — it reads the manifest and translates it into the actual write (Claude Code: `~/.claude/settings.json`; Cursor: `.cursorrules`; Codex: whatever).

### Two storage layers

| Layer | Writable? | What lives here |
| --- | --- | --- |
| Registered (`~/.melt/repos.patterns` roots) | No — read-only content | Canonical upstream content. `SKILL.md` (treated as tier 5) and/or native `0-melting-pot/`..`5-melting-pot/` subdirs (only if the user owns the repo). |
| Overlay (`~/.melt/<skill>/`) | Yes | User chunks `0-melting-pot/`..`5-melting-pot/*.md`, `patches/*.patch`, `patches/.failed/*.patch.failed`, `meta.md` (manifest for overlay-born skills), `.pending-transcript` handshake file, and **symlinks** to any upstream `N-melting-pot/` dirs the discovery pipeline detected. |

`origin` per skill is determined at discovery time:
- All content from registered → `reg`
- All content from overlay → `ovl`
- Both contribute → `mix`

## Cross-cutting invariants

- **Born at tier 0.** New chunks created by `mp:learn` always land at `0-melting-pot/`. No exceptions.
- **Patches never touch upstream.** Apply in-memory only. Upstream files are immutable.
- **Patch failures are LLM-triaged, not auto-resolved.** When a patch fails to apply, `patch.sh` records a marker in `~/.melt/<skill>/patches/.failed/` and **continues** attempting the rest of the patches. The marker contains enough information (patch hunk, upstream excerpt, reject output, timestamp) for `mp:learn patch-triage` to propose a fix to the calling LLM on a case-by-case basis. The apply pipeline itself is policy-free.
- **Tier dirs are named `N-melting-pot/` (where N ∈ 0..5).** Bare `0/`..`5/` are NOT recognized — avoids namespace collision with third-party repos and makes intent self-evident.
- **Partial-coverage rule (full-overlay mode).** If `mp/lib/discover.sh` detects upstream `N-melting-pot/` dirs for a skill, it symlinks them all into the overlay. If upstream has only some tiers (e.g., `0-melting-pot/`..`3-melting-pot/`), melting-pot does **not** mix-and-match partial upstream tiers with overlay-authored higher tiers — the overlay owns the entire tier stack for that skill (the symlinks bring the upstream content in, and overlay-authored chunks at the missing tiers fill the rest).
- **`SKILL.md` co-existence.** `SKILL.md` is indexed at tier 5 alongside any `5-melting-pot/*.md` files at the same tier — they merge alphabetically within tier 5, neither shadows the other.
- **Clean fork from `~/.sc/`.** melting-pot reads ONLY `~/.melt/repos.patterns`. The installer offers `--copy-from-sc` for one-time migration; no runtime fallback.
- **Installer never mutates harness config.** It emits a manifest; the calling LLM does the harness-specific write. Hooks themselves are harness-agnostic POSIX sh.
- **All scripts POSIX `sh`.** macOS-stock binaries only: `sqlite3`, `awk`, `sed`, `grep`, `find`, `git`, `shasum`. No Python, no `jq`, no third-party.
- **Atomic reindex.** Write to `index.db.tmp`, then `mv` over `index.db`. Same pattern as sc:search.
- **Hash-gated reindex.** Skip rebuild when SHA-256 of `<path>+<content>` for every discovered SKILL.md / meta.md / chunk / patch / symlink target matches the stored hash. Drift in any of these triggers atomic rebuild.

## File layout

```
melting-pot/
├── mp/
│   ├── lib/
│   │   ├── discover.sh          # discover_skills (registered+overlay union, symlinks upstream tier dirs), fm_field, body_after_fm, parse_patterns
│   │   ├── tier.sh              # walk N-melting-pot/, resolve_chunk_path, append status_history, detect full-overlay-mode
│   │   ├── patch.sh             # list_patches, apply_in_memory, validate_patch, record_failed_patch (→ .failed/)
│   │   └── compose.sh           # compose_skill(manifest + chunks + patches → md/json)
│   ├── search/{SKILL.md, action}
│   ├── load/{SKILL.md, action}
│   ├── list/{SKILL.md, action}
│   ├── crud/{SKILL.md, action}
│   └── learn/{SKILL.md, action}
├── install/
│   ├── install.sh               # one-shot bootstrap; emits manifest, NEVER mutates harness config
│   ├── REGISTER-HOOKS.md        # human-readable hook manifest for the agent to read
│   ├── task-intake.md           # global-rule text block to append (agent does the append)
│   └── hooks/
│       ├── melt-nudge.sh        # harness-agnostic POSIX sh
│       └── melt-resume.sh       # harness-agnostic POSIX sh
├── test/
│   ├── run-tests.sh
│   ├── skills/                  # synthetic fixtures (some w/ N-melting-pot/ tier dirs, some legacy SKILL.md, some mix, some with patches incl. failed)
│   └── golden/
│       ├── RUBRIC.md
│       └── queries.tsv
├── plans/
│   ├── architecture.md          # ← this file
│   ├── build_order.md
│   └── open_questions.md
├── INSTALL.md
└── README.md

~/.melt/                                # runtime state
├── repos.patterns                      # SOLE config path (clean fork from ~/.sc/)
├── default_repo                        # optional, used by mp:crud
├── hooks/                              # copied from install/hooks/ by install.sh
│   ├── melt-nudge.sh
│   └── melt-resume.sh
├── <skill>/                            # overlay
│   ├── meta.md                         # only for overlay-born skills
│   ├── 0-melting-pot/                  # tier dirs (suffix mandatory)
│   ├── 1-melting-pot/
│   ├── …
│   ├── 5-melting-pot/                  # may be a symlink to upstream/<skill>/5-melting-pot/
│   └── patches/
│       ├── 001-fix-typo.patch
│       ├── 002-remove-deprecated.patch
│       └── .failed/                    # LLM-triaged by mp:learn patch-triage
│           └── 002-remove-deprecated.patch.failed
├── learn/.pending-transcript           # SessionStart:clear handshake
├── learn/.tool-count-<sess>            # nudge throttle markers
├── search/index.db                     # FTS5
├── search/.index_hash
└── trash/                              # soft-deleted skills
```

## What changed vs. sc:* (the reference)

| Concept | sc:* | melting-pot |
| --- | --- | --- |
| Discovery unit | single `SKILL.md` per skill | manifest (`meta.md` or `SKILL.md`) + tier dirs `0-melting-pot/`..`5-melting-pot/` + overlay |
| Index row | one row per `SKILL.md` | one row per skill; content = patched + all chunks unioned |
| Storage layers | one (registered only) | two (registered + overlay), with `origin=reg|ovl|mix` |
| User customization of upstream | fork or nothing | git-patches, applied in-memory at index time; failures recorded to `.failed/` for LLM triage |
| Patch failure | n/a | recorded as marker file; never auto-skipped; `mp:learn patch-triage` proposes resolution |
| Tier dir naming | n/a | `N-melting-pot/` (suffix mandatory; bare `N/` not recognized) |
| Lifecycle | none (manual create/delete) | usage-driven promote/demote (remove at tier 0) + refactor/cascade/harvest/patch-triage via `mp:learn` |
| Hooks | none | Stop nudge + SessionStart:clear harvest, **harness-agnostic** |
| Installer | docs file | `install/install.sh` — emits manifest, does NOT mutate harness config |
| New skill scaffold | flat `<dir>/SKILL.md` | overlay `~/.melt/<skill>/meta.md` + `0-melting-pot/first.md` |
| Config | `~/.sc/repos.patterns` | `~/.melt/repos.patterns` (clean fork; no runtime fallback) |

## Related plans

- [build_order.md](build_order.md) — phased checkboxes, cherry-pick map, status
- [open_questions.md](open_questions.md) — open Q-IDs blocking implementation; resolved Q-001/003/007/008
