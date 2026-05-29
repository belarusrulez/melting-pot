---
name: flake:rerun
description: Use WHEN a test is intermittently failing in CI — quarantine and re-run it N times locally to confirm flakiness, then file a tracking issue rather than disabling silently.
---

> Test fixture for sc:search search system.

Flaky tests are a tax on velocity that compounds: people retry the build, learn to ignore reds, then miss a real regression. This skill runs a suspect test under controlled re-runs to quantify the flake rate, captures the failing seed/state, and produces a markdown report suitable for a tracking issue.

Typical usage:

```
flake-rerun pytest tests/test_oauth.py::test_token_refresh -n 100      # 100 runs
flake-rerun --pass-rate-threshold 0.95 ./run.sh -n 50                  # fail if <95% pass
flake-rerun --capture-on-fail -- pytest -k test_token_refresh -n 20    # save logs of every failure
flake-rerun --bisect-seed pytest tests/test_x.py -n 200                # find consistent fail seed
```

The `--capture-on-fail` mode is gold — it dumps stdout/stderr/coredump/timing for each failed iteration into `flake-runs/<test>/<iteration>/`, so you can compare three failing runs and see whether they share a common pattern (always at minute boundary, always after GC, etc.). The `--bisect-seed` mode tries to find a deterministic seed that always fails, which is often the missing ingredient for actually fixing the flake.

Do NOT use `flake-rerun` as a permanent "rerun until green" CI strategy — that hides the underlying flake, never fixes it. The right end state is: identify, classify (timing, ordering, env), and either fix or quarantine with an issue link. Related: `git:bisect` for regression hunting (different problem), `test:runner-smart` for normal runs, `coverage:report` for what's not even tested.
