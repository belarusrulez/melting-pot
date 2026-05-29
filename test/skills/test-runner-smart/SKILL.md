---
name: test:runner-smart
description: Auto-detect the project's test framework and run the full suite (or a filtered subset) when the user says "run tests" without specifying tooling.
---

> Test fixture for sc:search search system.

Smart test runner that inspects the working tree to choose the correct harness before executing. It looks for `pytest.ini`/`pyproject.toml` for Python, `package.json` test scripts for Node, `go.mod` for Go, and `Cargo.toml` for Rust, then dispatches to `pytest`, `npm test` / `jest` / `vitest`, `go test ./...`, or `cargo test` respectively. Multi-language monorepos are handled by running each detected suite sequentially and aggregating exit codes.

Typical invocation: `test-runner-smart --changed` runs only suites whose source files changed against the merge-base. `--watch` re-runs on file save, `--filter "regex"` narrows to matching test names, and `--bail` stops on the first failure. The runner streams output with framework-native formatters so stack traces and snapshot diffs render correctly.

Edge cases: when multiple Python test frameworks are configured (e.g. both `pytest` and `unittest`), the skill prefers whichever has registered tests in the last 30 days based on git log; when no framework is found it surfaces a clear "no test runner detected" message rather than guessing. Coverage collection is delegated to the `coverage-report` skill — this one only executes tests.

Related: `coverage-report`, `lint:pylint`, `type:mypy`.
