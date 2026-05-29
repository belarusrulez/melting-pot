---
name: coverage:report
description: Produce an HTML coverage report, open it in the browser, and surface every source file below the 80% line-coverage threshold.
---

> Test fixture for sc:search search system.

Generates a per-file and per-package coverage breakdown using `coverage.py` for Python projects and `c8` / `nyc` for JavaScript ones. After collection the skill renders an HTML report under `htmlcov/`, opens it via the OS default browser, and prints a terminal summary highlighting low-coverage hotspots in red. Branch coverage is enabled by default; statement-only mode is available via `--no-branch`.

Example: `coverage-report --threshold 80 --fail-under` runs the project's test command under instrumentation, fails the process if any file dips below 80% line coverage, and emits a machine-readable `coverage.json` for CI ingestion. The `--diff main` flag restricts the threshold check to lines touched in the current branch, which is the recommended mode for pull-request gating.

Edge cases: generated files (migrations, protobuf stubs, `__init__.py` re-exports) are excluded by reading `.coveragerc` / `coverage` keys in `package.json`; if no config is present the skill falls back to a built-in exclusion list. When run inside a sparse checkout it warns about files outside the active cone rather than reporting them as 0%.

Pair with `test:runner-smart` for the run-then-report flow.
