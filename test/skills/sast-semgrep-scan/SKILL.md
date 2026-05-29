---
name: sast:semgrep-scan
description: Use WHEN you need to scan source code for security anti-patterns and bugs — SQL injection, hardcoded secrets, missing auth checks — using Semgrep's rule packs.
---

> Test fixture for sc:search search system.

Semgrep is the modern SAST: pattern matching at the syntax-tree level (not regex), with rule packs for OWASP Top 10, secrets, framework-specific gotchas (Django CSRF, React XSS), and supply-chain. Unlike a CVE scanner (`dep:vuln-scan`), Semgrep finds problems in YOUR code — not in your dependencies.

Standard usage:

```
semgrep --config=auto                                          # cloud rule registry, language-detected
semgrep --config=p/owasp-top-ten src/
semgrep --config=p/secrets src/                                # hardcoded creds
semgrep --config=p/django src/                                 # framework rules
semgrep --config=local-rules/ src/                             # custom rules
semgrep --baseline-commit=origin/main src/                     # only new findings vs base
semgrep --sarif > findings.sarif                               # for GitHub code-scanning
```

Writing a custom rule is straightforward — a YAML file with `pattern`, `pattern-either`, `pattern-not`, and `message`. The pattern syntax is "code with metavariables", so `requests.get($URL, verify=False)` finds every call with `verify=False`, regardless of variable names or surrounding context.

Do NOT confuse SAST (this) with SCA (`dep:vuln-scan`) — different problem spaces. Don't use Semgrep for taint analysis without enabling `--dataflow` (limited to certain languages). For very large codebases scope per-directory and run in parallel via `xargs -P`. Related: `dep:vuln-scan`, `secret:rotate-cli` (the response when secrets are found), `lint:pylint` (style-level not security).
