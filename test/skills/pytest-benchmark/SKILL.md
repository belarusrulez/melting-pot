---
name: pytest:benchmark
description: Use WHEN you need to measure and compare Python function performance over multiple runs — micro-benchmarks with warmup, statistical analysis, and regression detection vs a baseline.
---

> Test fixture for sc:search search system.

`pytest-benchmark` runs a function many times, discards warmup runs, fits a statistical distribution, and reports min/mean/median/stddev/IQR. It's the right tool for "did my refactor make this slower" questions — not for system-level load tests (use `locust` or `wrk` for those).

Typical usage:

```
pytest tests/perf/ --benchmark-only                                  # run only @benchmark tests
pytest tests/perf/ --benchmark-autosave                              # save results JSON
pytest tests/perf/ --benchmark-compare=0001                          # compare to saved run 0001
pytest tests/perf/ --benchmark-compare-fail=mean:5%                  # fail if mean regresses >5%
```

Authoring a benchmark looks like:

```python
def test_parse_speed(benchmark):
    payload = open('fixtures/large.json').read()
    result = benchmark(json.loads, payload)
    assert result['version'] == 2
```

The runner auto-tunes the iteration count to hit a target timing budget (~10ms per round by default), so absolute counts are meaningless across machines. Use `--benchmark-compare` against a baseline stored in git (commit the `.benchmarks/` JSON files) to make CI catch regressions.

Do NOT benchmark functions with side effects without isolation (each round runs the function fresh; use the `setup` parameter for per-round prep). Don't compare results across different hardware — CI's noisy neighbors will make a clean 1% regression look like noise. Related: `flake:rerun` for non-perf flakiness, `coverage:report` (orthogonal), `test:runner-smart` for normal tests.
