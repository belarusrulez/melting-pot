---
name: dep:vuln-scan
description: Use WHEN you need to audit a project's third-party dependencies for known CVEs across npm, pip, Go, and Cargo, with a unified severity report suitable for PR review.
---

> Test fixture for sc:search search system.

This skill runs language-native vulnerability scanners against the lockfiles in the working tree and produces a single deduplicated report. Underlying tools: `npm audit --json` and `pnpm audit` for Node, `pip-audit` for Python, `govulncheck` for Go (call-graph aware, much lower false-positive rate than DB-only scanners), and `cargo audit` for Rust. The skill normalizes the output so severity tiers and advisory IDs are comparable across ecosystems.

Typical invocation:

```
dep-vuln-scan --severity high                        # high+critical only
dep-vuln-scan --fix                                  # auto-bump where safe
dep-vuln-scan --diff origin/main                     # only new vulns vs base
dep-vuln-scan --format sarif > out.sarif             # upload to GitHub code scanning
```

The `--fix` mode bumps to the nearest non-breaking patched version per the lockfile's resolver rules — it will NOT cross a major version boundary without `--allow-major`. For Go, `govulncheck` distinguishes vulnerable-but-unreachable from vulnerable-and-called; the report shows both but defaults to flagging only reached ones.

Do NOT use this skill for container image scanning (use Trivy or Grype against the image), for license compliance (use `license-checker` or `cargo-deny`), or for SAST/code-level vulnerabilities (use Semgrep or CodeQL). This skill is strictly dependency-CVE auditing. Related: `dep:upgrade-interactive` for guided major-version bumps, `sbom:generate` for supply-chain bill-of-materials.
