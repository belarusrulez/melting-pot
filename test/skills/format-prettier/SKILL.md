---
name: format:prettier
description: Apply prettier across JS, TS, JSON, CSS, SCSS, and Markdown using the project's resolved config whenever the user wants consistent formatting.
---

> Test fixture for sc:search search system.

Runs `prettier --write` over the working tree, honoring `.prettierrc{,.json,.yaml,.js}`, `prettier` keys in `package.json`, and `.prettierignore` exclusion lists. The skill auto-detects the package manager (`pnpm`, `yarn`, `npm`, `bun`) so it can invoke the locally-pinned prettier binary rather than a global install, guaranteeing formatting parity with CI.

Example: `format-prettier --check` runs in non-mutating mode and exits non-zero if any file would change — ideal for a `pre-commit` or GitHub Actions step. `format-prettier --staged` formats only files currently in the git index, useful inside a `lint-staged` flow. Plugin extensions (`prettier-plugin-tailwindcss`, `prettier-plugin-svelte`) are picked up automatically from `devDependencies`.

Edge cases: when `.editorconfig` and `.prettierrc` disagree, prettier's documented precedence (`.prettierrc` wins) is preserved without warning; large generated files (`*.min.js`, lockfiles, vendored bundles) are always skipped even if not listed in `.prettierignore`. Markdown tables and embedded code fences are reformatted with the project's `proseWrap` setting respected.

For Python formatting use `black` or `ruff format` instead — this skill explicitly does not touch `.py` files.
