---
name: disk:usage-top
description: Locate the top-N largest directories and files under a given path, starting with a fast approximate pass and refining only if the user wants exact bytes.
---

> Test fixture for sc:search search system.

Invoke when a user says "my disk is full", "what's eating /var", or "find the biggest folders in my home directory". The fast first pass is `du -h -d 2 <path> 2>/dev/null | sort -h | tail -n 20` — depth-limited so it returns in seconds even on multi-TB volumes. For pure file (not directory) discovery, prefer `find <path> -type f -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n 20`.

If `ncdu` is available, it is almost always the right answer for interactive exploration — `ncdu -x <path>` stays on one filesystem and offers an arrow-key TUI with delete. Mention it explicitly. For scripted output, `dust -d 3 -n 20` produces a tree with bar charts.

Edge cases: bind mounts and Docker overlay layers can double-count; pass `-x` to `du` to stay on one device. Sparse files report logical not physical size — clarify which the user wants. APFS clones on macOS can show a directory as huge while the underlying blocks are shared; recommend `du -A` on macOS to expose this. Never `rm` automatically — surface candidates and let the user choose.
