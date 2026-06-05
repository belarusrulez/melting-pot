# melting-pot — e2e ground-truth contract

> Wave-1 deliverable for the `docker-e2e-tests` harness. Every fact below is
> read from the code at the cited `file:line` and, where marked **[verified]**,
> confirmed by running the CLI against `test/skills/` in a sandboxed `$MP_HOME`.
> This is the spec QA scenarios and oracles assert against.

All five CLIs are POSIX-sh `action` scripts under `mp/<skill>/action`, each
sourcing the shared libs `mp/lib/{discover,tier,patch,compose}.sh`. They read
**only** `$MP_PATTERNS` (default `$MP_HOME/repos.patterns`); no legacy fallback
(Q-008). `$MP_HOME` defaults to `~/.melt`. Both are overridable by env — **the
container should set `MP_HOME`/`MP_PATTERNS` to a sandbox path per scenario** so
state assertions are isolated.

The invocation form everywhere is `sh <path-to-action> <args>` (skills are NOT
harness-registered slash-commands; the path IS the skill — `mp/search/SKILL.md`).

---

## 0. State map — where mutations land (the oracle's filesystem)

All runtime state is under `$MP_HOME` (`~/.melt`). After any op, an oracle
inspects these paths:

| Path | Written by | Meaning |
| --- | --- | --- |
| `$MP_HOME/repos.patterns` | installer / user / `doctor --write-sample` | registered roots, `<abs-root><TAB><pattern>` per line. `discover.sh:170` parses; `#`/blank skipped; pattern default `*`, `re:` prefix = ERE. |
| `$MP_HOME/search/index.db` | `search reindex` | FTS5 index (one row per skill). `search/action:31` |
| `$MP_HOME/search/index.db.tmp` | reindex (transient) | atomic build target; `mv`'d into place `search/action:278` |
| `$MP_HOME/search/.index_hash` | reindex | SHA-256 drift hash; auto-reindex compares `search/action:383` |
| `$MP_HOME/search/.last_queries` | `search` | last query axes, one per line `search/action:430` |
| `$MP_HOME/<skill>/meta.md` or `SKILL.md` | `crud scaffold` / user | manifest. `meta.md` (native) wins over `SKILL.md` (legacy). `discover.sh:273` |
| `$MP_HOME/<skill>/N-melting-pot/*.md` | `crud scaffold`, `learn promote/demote`, `learn harvest --apply` (create) | tier chunks, N∈0..5. New chunks born at tier 0. |
| `$MP_HOME/<skill>/N-melting-pot` (symlink) | `discover.sh` side-effect | when an upstream **registered** skill has tier dirs, discovery symlinks them into the overlay (Q-007). On Windows/MSYS it mirrors + drops `.mp-linked-from` sentinel. `discover.sh:313,85` |
| `$MP_HOME/<skill>/patches/NNN-*.patch` | `crud patch-add`, user | git-patch stack, applied in numeric order at index/compose time. `patch.sh:33` |
| `$MP_HOME/<skill>/patches/.failed/<patch-id>.failed` | `mp_apply_in_memory` (non-dry-run), via reindex/compose | failure marker; 4 delimited sections `--- patch / upstream excerpt / reject / timestamp ---`. `patch.sh:85` |
| `$MP_HOME/.trash/<ts>-<name>/` | `crud trash` | soft-deleted skill + `.mp-trash-meta.json` (`orig_path`). `crud/action:343` |
| `$MP_HOME/learn/.pending-transcript` | `melt-resume.sh` hook | handshake; `harvest --transcript` consumes via read-then-unlink. `learn/action:28,534` |
| `$MP_HOME/learn/.tool-count-<sess>` | `melt-nudge.sh` | decimal tool-call counter per session. `melt-nudge.sh:47` |
| `$MP_HOME/learn/.session-nudged-<sess>` | `melt-nudge.sh` | once-per-session nudge guard (presence = already nudged). `melt-nudge.sh:48` |

**Reserved overlay dirnames** skipped by discovery: `search`, `trash`, `learn`,
`hooks` (`discover.sh:398`; note `patch-triage` also skips `.trash` —
`learn/action:405`).

---

## 1. Per-CLI contract

### `mp-search` (`mp/search/action`)

Subcommands (`main` dispatch `search/action:694`): `search` (default — bare
`action q1 q2 q3` ⇒ `search`), `reindex`, `list-roots`, `doctor [--write-sample]`,
`-h|--help`.

`search [--limit N] [--format text|tsv|json] <q1> [q2] [q3] …`
- Flags BEFORE queries (`search/action:405`). `<3` queries ⇒ `WARN:` on stderr (`:423`), still runs.
- Three-axis Reciprocal Rank Fusion: each query top-5 by `bm25(skills,10,8,5,4)` (name/dirname/desc/content weights), fused `SUM(1/(10+rnk))` — RRF k=10 (`:447,470`). `axes>=2` ⇒ Convergence section, else Single-axis (`:516`).
- **text** (default): two sections; each hit `name axes=N score=… origin=… avg_tier=… hits=…  desc`, optional `patches=N applied [failed=M]`, then `→ <full path>`. **tsv**: `path⇥name⇥dirname⇥desc⇥score⇥axes⇥origin⇥avg_tier⇥hits⇥patches_applied⇥patches_failed` (11 cols). **json**: `{"results":[…]}` emitted whole by sqlite (`:457`), `{"results":[]}` when empty.
- **Auto-reindex**: every invocation except `reindex`/`help` recomputes the drift hash and rebuilds if changed (`:691,371`). Drift hash covers manifests, all tier chunks (`-L`), `patches/*.patch`, `.failed/*` markers, and symlink targets (`:285`).

Exit codes **[verified]** (`search/action:17-21`):

| code | meaning | verified trigger |
| --- | --- | --- |
| 0 | hits returned | 3-axis query matching a skill ⇒ 0 |
| 1 | no hits **OR** empty index (incl. missing `repos.patterns`) | nonsense query ⇒ 1; missing patterns file ⇒ **1, not 2** |
| 2 | config error — only `list-roots`/`doctor` with missing/invalid patterns | `list-roots`, `doctor` with no patterns ⇒ 2; bad flag ⇒ 2 |
| 3 | index error (sqlite/FTS5 failure, or `sqlite3` not on PATH) | — |

> **Oracle gotcha:** a *missing* `repos.patterns` does NOT make `search`/`list`
> fail with 2 — auto-reindex builds a valid empty index and the query returns
> **1 (no hits)**. Only `list-roots`/`doctor` surface 2 for missing config.

State touched: builds/refreshes `index.db`, `.index_hash`, writes `.last_queries`.
Triggers Q-007 symlink creation as a discovery side-effect.

### `mp-load` (`mp/load/action`)

`action <skill-name> [--format md|json] [--tiers 5,3,0] [--no-patches] [--with-history]`
- `<skill-name>` resolves by frontmatter `name:` OR dirname (`load/action:66`).
- Composes manifest + every chunk (tiers 5→0, alpha within tier) + patches applied in-memory (`compose.sh:48`). `SKILL.md` renders as tier-5 content. md header line: `origin=… | tiers present: […] | patches applied: N | patches failed: M` (`compose.sh:173`).
- `--no-patches` shows raw upstream (skips apply). `--tiers` filters. `--with-history` appends a "Status history" section.
- **Side-effect:** unless `--no-patches`, a failing patch writes a `.failed` marker (compose calls `mp_apply_in_memory` non-dry-run, `compose.sh:133`).

Exit codes **[verified]** (`load/action:14-17`): `0` composed (body on stdout);
`1` no such skill; `2` flag/usage error (incl. no arg).

> **Known wrinkle [verified]:** for a **mix-origin** skill whose overlay carries
> only `patches/` (no manifest) and whose upstream manifest is a `SKILL.md`, a
> *failing* patch makes `mp-load` exit **1** even though it still prints the
> composed document to stdout. The marker IS written when compose is exercised
> (confirmed by calling `mp_compose_skill` directly: `FAILED=[001-bad.patch]`,
> marker created with all 4 sections, reindex then reports `patches_failed=1`).
> Oracles asserting the marker should drive the apply via reindex or a clean
> overlay (manifest present), not rely on `mp-load`'s exit status here.

### `mp-list` (`mp/list/action`)

`action [--format text|tsv|json] [--root <abs-root>] [--name <glob|re:regex>] [--names-only] [--count]`
- Flat inventory, union of registered + overlay. `--name`/`--match` filters dirname (glob default, `re:` regex). `--root` restricts to one registered root (repeatable, validated against patterns). `--names-only` ⇒ frontmatter `name:` per line. `--count` ⇒ integer only.
- **tsv columns (10):** `name⇥dirname⇥origin⇥tiers_present⇥chunk_count⇥patches_count⇥patches_failed_count⇥description⇥path⇥root` (`list/action:248`). **json:** `{"results":[…],"count":N}` (9 fields, no `root`-less). **text:** grouped by `[origin] root (N skills)` with `tiers=/chunks=/patches=/failed=` + `→ path`.
- `tiers_present` rendered `[0,3,5]-melting-pot` or `legacy` (no tier dirs, SKILL.md-only) (`list/action:234`).

Exit codes **[verified]** (`list/action:16`): `0` listed ≥1; `1` empty; `2` config/bad flag.
Read-only (no state mutation), though discovery still creates Q-007 symlinks.

### `mp-crud` (`mp/crud/action`)

Subcommands (`crud/action:620`): `collision-check`, `scaffold`, `validate`,
`trash`, `restore`, `import-preview`, `patch-add`, `patch-list`, `patch-remove`,
`patch-validate`. Mutators take `--dry-run`. Exit: `0` ok, `1` problem, `2` usage/config.

| Subcommand | Stdout / behavior | State change | Verified |
| --- | --- | --- | --- |
| `collision-check <dirname>` | colliding paths on stderr | none | exit 1 if basename exists, 0 if free **[verified]** |
| `scaffold <name> [--native\|--legacy] [--target-dir D]` | "scaffolded native/legacy: …" | native (default): `$MP_HOME/<name>/meta.md` + `0-melting-pot/first.md`; legacy: `<target>/SKILL.md` | tier-0 chunk seeded **[verified]** |
| `validate <skill>` | `OK: <dir>` + `patches: total=/failed=/stale=` | none | exit 1 on missing manifest / bad frontmatter / unparseable patch; warns on bare `N/` dir, stale marker |
| `trash <skill>` | prints trash target path | `mv` skill → `$MP_HOME/.trash/<ts>-<name>/` + `.mp-trash-meta.json` | `orig_path` recorded for restore |
| `restore <trash-entry>` | "restored: <orig>" | `mv` back to `orig_path`, removes meta | refuses if target exists |
| `import-preview <root>` | TSV `path⇥name⇥desc⇥tiers⇥issues` | none (read-only) | — |
| `patch-add <skill> <file>` | prints new patch path | copies into `patches/`, renumbered to next `NNN-` slot | validates parse first |
| `patch-list <skill>` | TSV `patch-id⇥status` (`applies`/`failed`/`not-yet-attempted`) | none — **cheap, marker-based** | reports `not-yet-attempted` until a marker exists **[verified]** |
| `patch-remove <skill> <id>` | "removed: <id>" | rm patch + matching `.failed` marker | — |
| `patch-validate <skill>` | TSV `patch-id⇥applies\|failed` | none — **dry-run apply, no marker** | reports `failed` without writing marker **[verified]** |

> `patch-list` (cheap, reads markers) vs `patch-validate` (actually dry-runs
> `git apply --check`) diverge before any marker is written: list says
> `not-yet-attempted`, validate says `failed`. Both are read-only.

### `mp-learn` (`mp/learn/action`)

Subcommands (`learn/action:653`): `harvest`, `promote`, `demote`, `refactor`,
`cascade`, `patch-triage`. Mutators take `--dry-run`. Exit: `0` ok, `1`
nothing-to-do, `2` usage/config. Detailed in §2.

---

## 2. mp-learn lifecycle — observable before/after

**Tier movement is usage-quality driven only** — no time-decay, no
`promote_when`/`demote_when` rules (`learn/action:5`). The caller decides
good/bad and calls promote/demote. `use_count`/`last_used` are informational
metadata only.

### `promote <chunk>` / `demote <chunk>` **[verified]**

Chunk arg resolves as absolute path, `<skill>/<chunk-name>`, or
`<skill>/N-melting-pot/foo.md` (`learn/action:84`).

- **promote** (`:116`): `mv` chunk `N-melting-pot/` → `(N+1)-melting-pot/`, append `status_history` entry `{ tier: N+1, …, reason: "promoted from tier N" }`. Refuses at tier 5 with **exit 1** + WARN.
- **demote** (`:162`): `mv` to `(N-1)-melting-pot/` + history `"demoted from tier N"`. **At tier 0: removes the chunk** (`rm -f`), prints `removed: …`, after running `cascade` to flag dependents.

Verified before/after:
```
scaffold demo-skill   ⇒ 0-melting-pot/first.md (history: tier 0 "scaffolded")
promote demo-skill/first ⇒ chunk now at 1-melting-pot/first.md
                            history gains: tier 1 "promoted from tier 0"
                            rc=0; stdout "promoted: tier 0 -> 1"
demote demo-skill/first  ⇒ back to 0-melting-pot/, history "demoted from tier 1"
demote demo-skill/first  ⇒ rc=0, "removed: tier 0 chunk demoted out of the pot"; file gone
promote (chunk at tier 5) ⇒ rc=1, WARN "already at tier 5"
```
> **Oracle detail:** `mv` leaves the **empty source tier dir behind** (e.g.
> `0-melting-pot/` remains after promote). Assert on the *chunk file location*
> and the appended `status_history` entry, not on dir absence. `status_history`
> is append-only (`tier.sh:213`) — count entries to verify each move.
> Target-exists at the destination tier ⇒ exit 1 (no clobber, `:145`).

### `cascade <chunk>` (`learn/action:269`)

Walks every chunk's `depends_on`; prints `FLAG <file> depends on <skill>/<chunk> …`
for dependents. **Flag-only, never auto-mutates** (Q-002 v1). Always exit 0.
Invoked automatically (to stderr) by demote.

### `refactor [--yes]` (`learn/action:317`)

Proposes consolidation of chunks with identical normalized (lowercased,
whitespace-stripped) `title:` across the corpus. Prints groups with ≥2 members.
**v1 prints proposals only — no auto-consolidation even with `--yes`.** Exit 0
if overlaps found, 1 if none.

### `patch-triage [--format md|json]` (`learn/action:384`) **[verified]**

Sweeps every overlay `<skill>/patches/.failed/*.failed`. md: numbered proposals
per marker (Skill, Patch ID, Failed-at timestamp, reject output, Choices:
`regenerate`/`hand-rewrite`/`delete`/`defer`). json: `{"proposals":[…],"count":N}`.
Exit **0** when ≥1 marker, **1 when none** (`{"proposals":[],"count":0}` for json
**[verified]**).

The `.failed` flow end-to-end **[verified]**:
1. Bad patch in `$MP_HOME/<skill>/patches/NNN-bad.patch`.
2. reindex/compose runs `mp_apply_in_memory` → `git apply --check` fails → marker `<patch-id>.failed` written with 4 sections (`patch.sh:85`); apply **continues** to next patch (Q-001, never auto-stops).
3. reindex surfaces `patches_failed=1` in the FTS5 row (search tsv col 11 / list col 7). **[verified]**
4. `patch-triage` emits the proposal; resolution is `crud patch-remove` (delete) or hand-fix.

### `harvest [--transcript <path>] [--session <id>] [--apply]` (`learn/action:513`)

- **Transcript mode** (`--transcript` given, or `.pending-transcript` exists): reads the handshake **via read-then-unlink** (`:534`), prints the `.jsonl` path + size, instructs the agent to read it and re-invoke with JSON on stdin. Exit 0.
- **Live-context mode** (JSON on stdin): validates via `sqlite3 json_valid`; counts `$.proposals[]`. Without `--apply`: prints per-action summary, enacts nothing. With `--apply`: executes `create` (writes a new **tier-0** chunk via `mp_new_chunk_frontmatter`), `promote`, `demote`; `update` is reported but NOT auto-applied. Exit 2 if stdin is a TTY (`:552`); 1 on empty/invalid JSON.
- Stdin shape: `{"proposals":[{"action":"create","skill":…,"chunk_name":…,"title":…,"body":…,"session":…}, {"action":"promote","chunk":"…"}, …]}` (`:473`).

### The two recent learn changes (commit `d8d8ab0`)

**Promotion loop** — harvest only *births* tier-0 chunks; nothing reported "good
use", so the gradient never climbed. The fix is doc/workflow, not new code:
a use-reporting reflex wired into `mp-search` SKILL step 5 (`search/SKILL.md:74`),
the task-intake compile step (`install/task-intake.md`), and a new "Reporting
use" section + 4th trigger in `learn/SKILL.md:31`. **Observable for e2e:** after
an agent uses a skill whose overlay chunk helped, it should call
`learn promote <chunk>` → assert the chunk moved up a tier + a `status_history`
"promoted" entry appended. The *absence* of that call after a real use is the
loop-not-closed failure the change targets.

**Harvest quality guard** — chunks were born with session-specific IDs baked in,
polluting search. Added `_harvest_dup_warn` (`learn/action:491`): on a `create`
under `--apply`, runs the title through `mp-search` and, if a **same-skill** hit
scores `>= 0.12` RRF, emits a WARN to stderr (`:509`) — **advisory only, never
blocks** the create. **Observable:** create a chunk whose title duplicates an
existing same-skill chunk → expect the WARN on stderr AND the chunk still
created (exit unaffected).

---

## 3. Layering model

- **Registered layer** — every root in `repos.patterns`; canonical upstream the user didn't author. Glob (default `*`) or `re:` regex on the skill dir basename (`discover.sh:358`).
- **Overlay layer** — `$MP_HOME/<skill>/`; user-owned. Holds overlay-authored `N-melting-pot/` chunks, `patches/`, optional `meta.md`/`SKILL.md`.
- **Union & origin** (`discover.sh:344`, emits `path⇥origin⇥kind`):
  - `reg` — only registered contributes.
  - `ovl` — only overlay (overlay-born skill).
  - `mix` — both (overlay has patches and/or overlay chunks alongside upstream). **[verified]** adding just a `patches/` dir to an overlay flips a registered skill `reg`→`mix`.
- **kind**: `legacy` (SKILL.md-only, no tier dirs anywhere) vs `native` (≥1 tier dir).
- **Q-007 symlink side-effect [verified]:** if an upstream registered skill has tier dirs, discovery symlinks `<overlay>/N-melting-pot → <upstream>/N-melting-pot` and **rewrites the emitted path to the overlay** so search/load/list read uniformly through the overlay (`discover.sh:459`). Confirmed: a registered-only `git-rebase` gets `~/.melt/git-rebase/{0,3}-melting-pot` symlinks after any discovery run, origin still `reg`. On Windows/MSYS without symlinks: mirror dir + `.mp-linked-from` sentinel (`discover.sh:85`).
- **Patches apply in-memory at index time** — never mutate upstream files. `mp_apply_in_memory` (`patch.sh:150`) seeds a tmp git work-tree with `upstream.md`, applies `patches/*.patch` in numeric order, commits each success so later patches stack; failures record a marker and continue. The patched union (chunks + patched manifest body) is what gets indexed (`search/action:110`).
- **tiers / avg_tier / hits** (`tier.sh`): tier dirs `N-melting-pot/` only, N∈0..5 (bare `N/` ignored, Q-007). `avg_tier` = chunk-count-weighted mean tier, 1-decimal (`tier.sh:83`). `hits` = `[tier:count, …]` (`tier.sh:108`). A legacy SKILL.md counts as 1 chunk at tier 5 (`avg_tier=5.0`, `hits=[5:1]`).

---

## 4. Install / registration seam

`install/install.sh` (deterministic; never touches harness config — Q-003,
verified by a before/after SHA-256 invariant check on `~/.claude/settings.json`,
`install.sh:371`). Flags: `--dry-run`, `--emit-manifest-only`, `-h`. Exit:
`0` ok, `2` bad flag, `3` missing source, `4` Q-003 breach.

What it does (`install.sh:188`):
1. Seeds `$MP_HOME` + `learn/ hooks/ search/ trash/`.
2. Writes `repos.patterns` **stub only if missing** (never overwrites).
3. Copies hooks → `$MP_HOME/hooks/{melt-nudge,melt-resume}.sh` (chmod +x).
4. Per shipped skill (any `mp/*/SKILL.md`): `mkdir $MP_HOME/<skill>/` + link its `action` → `$MP_HOME/<skill>/action`. Symlink on macOS/Linux; **shim that execs the repo action with `MP_LIB_DIR` set** on Windows/MSYS (`install.sh:166`).
5. Emits the harness-agnostic manifest to `$MP_HOME/REGISTER-HOOKS.md` (absolute paths baked in; repo copy uses `~/.melt/…` placeholders).
6. Copies `install/task-intake.md` → `$MP_HOME/task-intake.md`.
7. Prints "Next steps" for the calling LLM.

**Manual steps a container must perform** (the installer can't portably script
these — `install/INSTALL.md`, `REGISTER-HOOKS.md`):
- **Register each `mp/*/SKILL.md`** with the harness (only agent-side step for skills).
- **Seed `repos.patterns`** to point at a skills root (e.g. `test/skills`) — `printf '<abs-root>\t*\n' > $MP_HOME/repos.patterns`.
- **Wire the two hooks** into harness config.
- **Append `task-intake.md`** to the global rules file (exactly once).
- **Build the index + smoke test:** `sh $MP_HOME/search/action reindex` then `sh $MP_HOME/list/action --count`.

**The two hooks** (harness-agnostic, plain-text stdout, always exit 0):

| Hook | Event | Trigger | Needs | Observable |
| --- | --- | --- | --- | --- |
| `melt-nudge.sh` | `Stop` | each assistant turn end | `MP_HOME`; `MP_NUDGE_THRESHOLD` (default 20); session id (`$1`/`MP_SESSION_ID`/`ppid-$PPID`) | increments `.tool-count-<sess>`; once `>= threshold` AND not already nudged, prints the "run mp-learn before /clear" nudge and touches `.session-nudged-<sess>`. Counter + marker files are the assertion surface. |
| `melt-resume.sh` | `SessionStart:clear` | session cleared | `MP_HOME`; **live transcript path** via `$1`/`MP_PRIOR_TRANSCRIPT` (+ optional prior session id) | atomically writes transcript path to `learn/.pending-transcript` (tmp-then-rename); prints resume-or-harvest prompt. With no transcript, prints fallback prompt and writes nothing. |

> Both hooks need the harness to supply the **live transcript / session id** as
> args or env. In a container the e2e harness must inject these (e.g. pass a
> real `.jsonl` path to `melt-resume.sh $TRANSCRIPT $UUID`) to exercise the
> harvest handshake; otherwise `.pending-transcript` is never written.
> Round-trip to assert: run `melt-resume.sh <path>` → file contains `<path>` →
> `learn harvest` (no flag) consumes it (read-then-unlink) → file gone.

---

## 5. Reuse plan — golden corpus as e2e ground truth

`test/golden/` + `test/skills/` is a ready-made relevance benchmark for "did the
agent pick the right skill".

- **Corpus:** `test/skills/` — ~79 skills **[verified count via `list --count`]**. Mostly legacy single-`SKILL.md` distractors spanning git / docker / k8s / csv / aws / gcp / observability / security. Two native fixtures exercise the post-Q-007 layout: `git-rebase` (SKILL.md + `0-melting-pot/` + `3-melting-pot/`) and `melting-pot-native-demo` (`meta.md` + `0`/`5-melting-pot/`, **no SKILL.md**).
- **Graded queries:** `test/golden/queries.tsv` — 119 graded data rows across 55 qids **[verified]** (129 file lines = 1 header + 9 `# category:` comment lines + 119 data rows; columns `qid axis1 axis2 axis3 target_skill grade`). Grades per `RUBRIC.md`: **2** = the answer (exactly one per qid — 55 grade-2 rows, must ideally rank #1), **1** = useful near-miss (46 rows, partial credit), **0** = adversarial distractor (18 rows, must NOT rank #1), implicit **-1** = everything unannotated (must not rank #1). Five categories: exact-vocab / synonym-jargon / intent-only / cross-domain-ambiguity / adversarial (`# category:` comment lines).
- **Metrics the rubric is built for:** precision@1, precision@3, MRR, NDCG@5. Grade-1 rows exist specifically so NDCG isn't binary.

**How an e2e oracle uses it:** seed `repos.patterns → test/skills`, `reindex`,
then for each `qid` run `sh mp/search/action --format tsv axis1 axis2 axis3` and
read column 2 (`name`) / column 1 (`path`→dirname) of ranked rows. Score the
ranking against that qid's `(target_skill, grade)` rows:
- **precision@1 / NDCG@5 / MRR** from the grade-2 target's rank.
- **Adversarial guard:** assert the #1 result is *some* annotated skill for that qid (grade 2/1/0) — an unannotated #1 means coverage escaped the rubric. A grade-0 at #1 is a hard fail (lexical-bias regression).

This is the strongest "right skill" signal available — it lets the e2e harness
distinguish a real `claude -p` agent **finding** the right skill from one merely
running the CLI. For the *full-pipeline* loop (search → load → use → promote),
the two native fixtures (`git-rebase`, `melting-pot-native-demo`) are the ones
with overlay chunks to promote/demote, so they're the fixtures the promotion-loop
scenarios should target.

**Fixtures the container should seed:**
1. `repos.patterns` → `<repo>/test/skills` (registered layer).
2. A clean sandbox `$MP_HOME` per scenario (overlay layer starts empty).
3. For mutation scenarios: `crud scaffold <name>` to mint an overlay-born native skill (gives a tier-0 chunk to promote/demote without touching the corpus).
4. For patch scenarios: drop a known-bad and a known-good `patches/NNN-*.patch` under an overlay skill to exercise the `.failed` marker + triage flow.
5. For hook scenarios: a fixture `.jsonl` transcript path to feed `melt-resume.sh`.

---

## Cross-cutting invariants oracles can rely on

- **Born at tier 0** — every new/harvested chunk lands at `0-melting-pot/` (`tier.sh:340`, `learn/action:609`).
- **Append-only status_history** — every promote/demote adds an entry, none removed (`tier.sh:213`).
- **Policy-free patch apply** — a failed patch records a marker and the stack CONTINUES; never auto-skips a user patch, never auto-stops (Q-001, `patch.sh:1`).
- **Atomic index swap** — reindex builds `index.db.tmp` then `mv`'s (`search/action:278`); an empty index is a valid state (exit 0, "indexed 0 skill(s)").
- **Read-then-unlink handshake** — `harvest` consumes `.pending-transcript` once (`learn/action:534`); a re-run won't re-fire.
- **Installer never mutates harness config** — Q-003, enforced by SHA-256 invariant (exit 4 on breach).
