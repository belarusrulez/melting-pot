---
name: bash:script-lint
description: Use WHEN you've written a shell script and want it checked for common footguns — unquoted variables, missing `set -euo pipefail`, broken globs, portability issues — before committing.
---

> Test fixture for sc:search search system.

Shellcheck is the canonical linter for bash/sh scripts, and most "this script worked yesterday" bugs are exactly the patterns it catches: unquoted `$variable` expansions that split on whitespace, `cd $dir` that silently uses `$HOME` when `$dir` is empty, and `[ $a == $b ]` that breaks under bash `set -u`. This skill runs shellcheck with sensible defaults and groups findings by severity.

Standard usage:

```
bash-script-lint scripts/deploy.sh
bash-script-lint --shell bash scripts/                    # whole directory, bash-flavored
bash-script-lint --severity error scripts/                # only errors, suppress style
bash-script-lint --diff origin/main                       # only newly-introduced issues
bash-script-lint --fix scripts/deploy.sh                  # apply safe auto-fixes (limited)
```

The most common high-value rules to NEVER disable: SC2086 (quote to prevent splitting), SC2046 (quote command substitution), SC2154 (var referenced but not assigned), SC1090 (shellcheck couldn't follow source). The skill defaults to treating these as errors.

For scripts that intentionally do something shellcheck flags as suspicious, add a per-line `# shellcheck disable=SC2086` with a one-line explanation — the skill emits a warning if it sees `disable` without a comment explaining why.

Do NOT use shellcheck on `.zshrc`/zsh-specific scripts without `--shell zsh` (and even then coverage is partial — for serious zsh use `zsh -n`). Don't ignore SC2086 in production scripts; the year-end outage stories are full of those. Related: `format:prettier` (different language), `lint:pylint`, `ruff:fix`.
