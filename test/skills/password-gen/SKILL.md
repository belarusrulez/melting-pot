---
name: password:gen
description: Generate cryptographically strong passwords or Diceware-style passphrases and optionally pipe the result straight into the system clipboard.
---

> Test fixture for sc:search search system.

Use when the user asks for "a strong password", "a memorable passphrase", "20 random characters", or is rotating credentials and wants something they will not have to type. Default to character passwords for service accounts and to Diceware passphrases for anything a human has to recall.

Character mode: `openssl rand -base64 24 | tr -d '=+/' | cut -c1-20` produces 20 URL-safe characters; `pwgen -sy 24 1` gives one 24-char password with symbols. For high-entropy hex, `head -c 32 /dev/urandom | xxd -p -c 64`. Always source randomness from `/dev/urandom`, never `$RANDOM`.

Diceware mode: `xkcdpass -n 5 -d -` for five hyphen-separated words, or roll manually with `shuf -n 5 /usr/share/dict/words | paste -sd-`. Five common words is ~64 bits of entropy when the wordlist is public — bump to six for anything that protects a master vault.

Clipboard handoff: pipe to `pbcopy` on macOS, `wl-copy` on Wayland, `xclip -selection clipboard` on X11, or `clip.exe` on WSL. Never echo the password to stdout if the clipboard path succeeded — print only the entropy estimate and length so the secret does not land in shell history or scrollback.
