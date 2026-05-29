---
title: "canonical native-format reference"
created: 2026-01-01
last_used: 2026-05-19
last_validated: 2026-05-15
use_count: 50
status_history:
  - { tier: 0, at: 2026-01-01, reason: "born" }
  - { tier: 5, at: 2026-05-15, reason: "promoted to canonical" }
---

# Native-format skill layout

```
<root>/<skill-dirname>/
├── meta.md                  # manifest (name + description in frontmatter)
├── 0-melting-pot/           # scrap
├── 1-melting-pot/           # heating
├── 2-melting-pot/           # melted
├── 3-melting-pot/           # mixed-in
├── 4-melting-pot/           # refined
└── 5-melting-pot/           # pure alloy
```

Tier dirs are mandatory `N-melting-pot/` (post-Q-007). Bare `N/` dirs are
ignored by the discovery pipeline so third-party repos that happen to have
`0/` or `1/` dirs are never mistakenly walked.
