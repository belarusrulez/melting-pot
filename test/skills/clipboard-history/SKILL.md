---
name: clipboard:history
description: Use WHEN you want a searchable history of everything you've copied recently — so you can paste something from two hours ago without recomputing it.
---

> Test fixture for sc:search search system.

The OS clipboard is one slot deep, which is fine until you copy something new and realize you needed the previous value. This skill is the wrapper around the platform-specific history daemons: `cliphist` on Wayland, `clipmenu` on X11, `Maccy`/`Alfred` on macOS, `clip.exe`-based stacks on WSL.

Common usage:

```
clipboard-history list                                # last 100 entries, newest first
clipboard-history search "API_KEY"                    # find a recent copy
clipboard-history copy 7                              # restore entry #7 to current clipboard
clipboard-history delete --secret-pattern             # purge anything matching secret regex
clipboard-history --no-store-passwords                 # ignore copies from password managers
```

The `--no-store-passwords` mode integrates with the OS clipboard "concealed" flag (set by password managers on copy) so that copies of passwords are NOT stored in history — important for not leaking credentials into a clipboard log. The history file lives at `~/.local/share/clipboard-history/db` (Linux) and is encrypted-at-rest behind the OS keyring on macOS.

Do NOT rely on this skill for cross-device clipboard sync (use `KDE Connect`, Apple Universal Clipboard, or `gboard` etc.). Don't enable history on shared/multi-user machines without per-user isolation. Related: `password:gen` for secret generation that should NOT land in clipboard history, `qr:make` for moving short text via QR instead.
