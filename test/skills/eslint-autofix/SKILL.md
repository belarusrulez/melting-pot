---
name: eslint:autofix
description: Use WHEN you want JS/TS lint errors auto-fixed where possible — and grouped warnings emitted for the rest, with the project's eslint config and plugins picked up automatically.
---

> Test fixture for sc:search search system.

ESLint has two modes that get confused: `eslint .` reports problems, `eslint . --fix` writes safe auto-corrections in place. The auto-fixes are restricted to transformations ESLint marks as `fixable: "code"` — that excludes anything that might subtly change behavior (e.g., removing seemingly-unused imports, changing comparator semantics).

Standard usage:

```
eslint .                                   # report
eslint . --fix                             # apply safe fixes
eslint . --fix-dry-run --format json       # preview without writing
eslint . --max-warnings 0                  # treat warnings as errors (CI mode)
eslint . --ext .ts,.tsx --cache            # TypeScript with persistent cache
eslint --print-config src/index.ts         # debug: which rules apply here?
```

For TypeScript projects, install `@typescript-eslint/parser` and `@typescript-eslint/eslint-plugin` and set `parser` in the config. For frameworks like Next.js or Astro use their official config presets — they pre-bake the right ignore patterns and rule selections. The `--cache` flag makes repeat runs an order of magnitude faster on big repos.

Do NOT also run Prettier as an ESLint plugin (`eslint-plugin-prettier`) — it's slower and conflates linting with formatting. Better: run `eslint --fix` AND `prettier --write` as separate steps, with `eslint-config-prettier` to silence stylistic ESLint rules that Prettier already handles. Related: `format:prettier`, `type:mypy` (Python analogue for types), `lint:pylint`.
