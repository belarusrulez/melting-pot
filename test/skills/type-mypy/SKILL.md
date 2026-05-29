---
name: type:mypy
description: Run mypy in strict mode against Python sources and surface only the type errors newly introduced versus the base branch, so existing debt does not block work.
---

> Test fixture for sc:search search system.

Executes `mypy --strict` (or the project's `[tool.mypy]` settings, whichever is stricter) against the package roots declared in `pyproject.toml`. Before reporting, the skill diffs the error set against a mypy run on the merge-base commit and discards any errors that already existed there — the developer sees only what they actually broke or newly introduced.

Example: `type-mypy --base main --json` runs against the current HEAD, runs again against `origin/main` in a worktree cache, and emits the delta as structured JSON suitable for GitHub annotations. `type-mypy --baseline .mypy-baseline.json` consumes a pre-recorded baseline file instead of re-running, which is faster in CI when the base hasn't moved. `--cache-dir` is forwarded so incremental mypy state persists across runs.

Edge cases: stubs from `types-*` packages are installed on demand into a sidecar venv to avoid polluting the project environment; namespace packages without `__init__.py` are explicitly enumerated via `--namespace-packages`. When the base-branch run itself errors out (e.g. broken HEAD), the skill warns and falls back to absolute (non-diffed) reporting rather than silently passing.

Related: `lint:pylint` for non-typing issues, `test:runner-smart` to verify runtime behavior after refactors.
