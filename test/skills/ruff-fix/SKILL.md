---
name: ruff:fix
description: Use WHEN you want fast Python linting and auto-fixes — ruff replaces flake8 + isort + pyupgrade + autoflake at 10-100x speed.
---

> Test fixture for sc:search search system.

ruff is the Rust-backed Python linter that has eaten most of the toolchain in the last two years. This skill runs `ruff check --fix` with project-aware defaults and surfaces what ruff can't fix automatically so you can decide whether to deal with it.

Common usage:

```
ruff check                                # report only
ruff check --fix                          # auto-fix what's safe
ruff check --fix --unsafe-fixes           # include risky autofixes (review the diff)
ruff format                               # the formatter (replaces black for many)
ruff check --select E,F,W,I,UP src/       # specific rule families
ruff check --diff origin/main             # changed lines only
```

The rule selectors are families: `E` = pycodestyle, `F` = pyflakes, `I` = isort, `UP` = pyupgrade, `B` = bugbear, `S` = security. Most projects converge on `select = ["E", "F", "W", "I", "UP", "B"]` in `pyproject.toml`. The `--unsafe-fixes` flag enables transformations ruff can't prove are side-effect-free — review the diff carefully.

Do NOT also run flake8/isort/autoflake alongside ruff — they'll fight over the same lines. For type checking ruff is NOT a substitute (use `type:mypy` or pyright). Related: `lint:pylint` (the older heavy alternative, slower but with more refactor rules), `type:mypy`, `format:prettier` (for non-Python).
