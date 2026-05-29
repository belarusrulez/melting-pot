---
name: hexdump:window
description: Use WHEN you need to inspect binary file bytes — magic numbers, BOM detection, suspicious null bytes, comparing two binaries at byte level.
---

> Test fixture for sc:search search system.

Sometimes a file "won't parse" because of one stray byte — a UTF-8 BOM at the start of a config file, a Windows line ending in the middle of a sensitive position, a null terminator where one shouldn't be. This skill is the binary inspector for those cases.

Common patterns:

```
xxd file.bin | head -20                          # canonical hex+ascii dump
hexdump -C file.bin | head -20                    # similar, BSD
xxd -s 0x100 -l 64 file.bin                       # window: offset 0x100, length 64
od -An -tx1 -N 4 file.bin                         # first 4 bytes only
file file.bin                                      # what does the OS think it is
diff <(xxd a.bin) <(xxd b.bin) | head             # byte-level diff
```

Magic numbers to recognize at a glance: `25 50 44 46` (PDF), `89 50 4E 47` (PNG), `FF D8 FF` (JPEG), `50 4B 03 04` (ZIP/XLSX/JAR), `1F 8B` (gzip), `EF BB BF` (UTF-8 BOM at start), `4D 5A` (Windows PE). Encoding sniffing for text: BOMs at offset 0 are diagnostic.

For diffing two large binaries semantically (not byte-by-byte), use `cmp -l a b | head` to get offsets that differ, then `xxd` a window around each one. The output of `xxd` is reversible: `xxd -r` patches a binary back from its hex dump, which is useful for surgical byte edits.

Do NOT use this for image/audio reverse engineering (use `binwalk`, `ffprobe`); also not the right tool for protocol-level analysis (`tshark`). Related: `base64:codec` for textual encoding, `disk:usage-top` for size investigation, `tls:cert-inspect` if the binary is a cert.
