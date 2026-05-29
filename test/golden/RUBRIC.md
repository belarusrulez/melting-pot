# Golden-relevance rubric

This rubric defines how queries in `queries.tsv` are graded for the `sc:search` ranking-quality test suite. Every `(qid, target_skill)` annotation in `queries.tsv` uses one of the four grade levels below.

The grades feed precision@1, precision@3, MRR, and NDCG@5 metrics. NDCG specifically needs more than binary signal — that is why a non-trivial number of grade-1 annotations is mandatory.

---

## Grade definitions

### Grade 2 — Perfect (must rank #1 ideally)

This skill **IS** the answer to the query. A user typing the query and opening the top-ranked result would read the SKILL.md and immediately have what they need to solve the task. No further searching, no "well, this is close but…" — direct hit.

For every query (`qid`) there is **exactly one** grade-2 target. Multi-target perfect matches are an anti-pattern; if you can't pick one over another, the query is too ambiguous and should be rewritten or split.

**Worked example.** Query axes:

- `axis1`: "binary search the first bad commit"
- `axis2`: "bisect regression in recent history"
- `axis3`: "find which commit introduced the regression"

→ `git-bisect` is the grade-2 target. The skill's description (`Use WHEN a regression appeared somewhere in recent history and you need to binary-search commits…`) is a near-verbatim restatement of the query's intent.

### Grade 1 — Useful related / near-miss

Same domain or overlapping concern, partial vocabulary match, but **not** the primary answer. A user pointed at this skill would learn something adjacent but would have to look further to actually solve the task. Used for partial-credit metrics (NDCG@5, MRR with discount) — without these annotations NDCG collapses to a binary signal and the metric loses resolution.

Typical grade-1 patterns:

- Same cluster, different sub-problem (e.g. `git-cherry-pick` for a "rebase" query — both rewrite history, but one moves commits and one reorders them).
- Adjacent in a workflow (e.g. `csv-merge` for a "deduplicate CSV" query — the skill's own description mentions dedup, but it points to `csv-dedupe` for the actual single-file case).
- One step away in the call graph (e.g. `coverage-report` for a "run my tests" query — coverage runs tests as a side effect, but `test-runner-smart` is the direct answer).

**Worked example.** Same query as above (`git-bisect` target) → `git-rebase` could be grade 1 if the user might plausibly need rebase context after identifying the bad commit, OR grade 0 if rebase is just lexical "git" overlap with no functional relation. The grader chooses based on whether the skills' bodies cite each other or share a meaningful workflow link.

**Minimum coverage.** At least 5 query-rows in `queries.tsv` must use grade 1, distributed across queries (not all on one qid). Critic enforces.

### Grade 0 — Adversarial distractor (must NOT rank #1)

Lexically plausible match — the skill's description shares vocabulary with the query — but solves a **different** problem. A user who clicked into it would realize "this is the wrong skill" within seconds. Used to catch ranking failures where lexical signal overwhelms semantic intent.

Grade-0 annotations are the discriminative test: a ranker that returns grade-0 at #1 is failing in a specific, testable way (lexical-match bias). Every grade-0 row must have a defensible "shared vocab → different problem" story.

**Worked example.** Query axes:

- `axis1`: "scan my dependencies for vulnerabilities"
- `axis2`: "dependency security scanner"
- `axis3`: "find vulnerable packages in my project"

Grade 2: `dep-vuln-scan` (the description literally says "audit a project's third-party dependencies for known CVEs").
Grade 0: `port-scan-local` (shares "scan" + "security" / "vulnerable" / network-attack adjacency, but is strictly localhost socket enumeration — different problem entirely).

Another example, the architect's `rebase` / `rebalance` / `reshape` lexical neighbor:

Query: "rebase database shards" (target: `db-rebalance-shards` at grade 2)
Distractor: `git-rebase` at grade 0 — shares the literal word "rebase" but is about commit history, not data sharding.

**Minimum coverage.** At least 5 query-rows in `queries.tsv` must use grade 0, distributed across queries. Critic enforces.

### Implicit grade -1 — Everything else in the corpus

Skills NOT annotated for a query are implicit grade -1. They must not rank at #1 for that query. The harness verifies this by checking that the #1 result is one of the annotated skills (any of grade 2/1/0) — if it is something unannotated, the ranking failed in a way that escaped the rubric's coverage. The query is then a candidate for adding more grade-0 annotations to extend the rubric, or for being marked as an unrepresentative test.

No annotation rows for grade -1 exist in `queries.tsv` — the absence IS the annotation.

---

## Boundary calls

When grading is ambiguous, prefer narrower grades:

- **2 vs 1 ambiguous?** Demote to 1. Grade 2 is a strong claim — it says this is THE answer. If two skills could each be "the" answer for a query, the query is bad, not the rubric.
- **1 vs 0 ambiguous?** Prefer 1 if there is any plausible workflow link (skills cite each other; one would direct a user to the other). Prefer 0 if the link is purely lexical with no functional path.
- **0 vs -1 ambiguous?** Prefer 0 if there's enough lexical overlap that a ranker plausibly *could* mistakenly promote it. The point of grade 0 is to catch the mistakes; if no ranker would ever return it at #1, there's no value in annotating.

When in doubt, ship the grade and let critic flag it on review.

---

## What grades are NOT

- Not a quality judgment of the skill itself. A well-written but off-topic skill is grade 0 / -1. A poorly-written skill that happens to be the answer is grade 2.
- Not a continuous score. Use exactly 2 / 1 / 0; don't invent 1.5 or 0.5. The metric formulas (NDCG, MRR) need discrete grades.
- Not directional. Grade is per-query, not per-skill. The same skill can be grade 2 for one query and grade 0 for another — that is the entire point.

---

## TSV schema

`queries.tsv` columns (tab-separated, header row required, real tab characters):

| Column | Meaning |
| --- | --- |
| `qid` | stable query id, e.g. `q001` — repeats across rows (one row per annotation) |
| `axis1` | literal phrase the user might type |
| `axis2` | synonym / jargon phrasing for the same concept |
| `axis3` | intent / goal phrasing (description-style, not keyword-style) |
| `target_skill` | directory name under `test/skills/` |
| `grade` | one of `2` / `1` / `0` |

The three axes per row are constant for a given `qid` — the variation is in the `(target_skill, grade)` pair. A single query with one grade-2 target plus one grade-1 and one grade-0 distractor appears as three rows.

Category markers as `# category: <name>` comment lines group queries into the five required buckets (exact-vocab / synonym-jargon / intent-only / cross-domain-ambiguity / adversarial).
