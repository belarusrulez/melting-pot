---
name: lint:pylint
description: Run pylint with project-aware defaults and group findings by severity tier when the user wants to lint Python before commit or in CI.
---

> Test fixture for sc:search search system.

Wraps `pylint` with a curated baseline: enables the `useless-suppression` check, disables overly noisy stylistic rules (`missing-docstring`, `too-few-public-methods`), and respects any project `.pylintrc` or `[tool.pylint]` block in `pyproject.toml` on top of those defaults. Output is regrouped into Fatal, Error, Warning, Refactor, and Convention buckets with counts per file, making it obvious which violations actually block merge.

Example: `lint-pylint src/` lints the package and prints the grouped summary; `lint-pylint --diff origin/main --fail-on error,fatal` only flags lines introduced on the current branch and exits non-zero exclusively on error-tier or worse findings. The `--fix-imports` flag invokes `isort` afterwards to auto-resolve the most common `wrong-import-order` complaints.

Edge cases: respects per-directory `# pylint: disable=...` blocks; for Django/Flask projects it auto-loads `pylint-django` or `pylint-flask` plugins when those frameworks are detected in `requirements*.txt`. Concurrent runs on large repos use `--jobs=0` to saturate cores, with a `--jobs N` override for resource-constrained CI agents.

Companion skills: `format:prettier` (for non-Python files), `type:mypy`.
