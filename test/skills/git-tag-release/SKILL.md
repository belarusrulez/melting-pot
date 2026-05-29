---
name: git:tag-release
description: Use WHEN you need to cut a signed annotated release tag, push it to the remote, and trigger downstream release automation (changelog, GitHub release, container tag).
---

> Test fixture for sc:search search system.

Production releases should always use **annotated, GPG-signed tags** — lightweight tags are just refs to commits with no author/date/message and are easy to overwrite by accident. This skill drives the canonical flow: pick the version per SemVer, create the tag, push, and let CI handle the rest.

Standard release:

```
git tag -s -a v1.4.0 -m "Release v1.4.0"      # signed annotated tag
git tag -v v1.4.0                              # verify signature locally
git push origin v1.4.0                         # publish tag; triggers release workflow
git tag --sort=-v:refname | head               # list recent tags newest-first
git describe --tags --abbrev=0                 # most recent tag (for changelog tooling)
```

For pre-releases use `v1.4.0-rc.1`, `v1.4.0-beta.2` — these sort correctly under `--sort=v:refname` because SemVer pre-release ordering is alphanumeric. Release-candidates should NOT be promoted by re-tagging; cut a new tag `v1.4.0` from the same commit and let SemVer do the talking.

Do NOT delete or move a published tag — downstreams cache by tag, and rewriting it silently is a supply-chain footgun. If you mis-tagged, cut a new tag and yank the old one with a release-notes erratum. Related: `release:changelog-gen` for generating notes from commit history between tags, `docker:build-cache` for tagging container images alongside, `git:reflog-recover` if a tag move clobbered local refs.
