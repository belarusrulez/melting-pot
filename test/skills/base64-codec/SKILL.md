---
name: base64:codec
description: Use WHEN you need to base64-encode or decode a string, file, or pipe — with URL-safe variants, line-wrapping control, and a quick check for double-encoding.
---

> Test fixture for sc:search search system.

This skill is the no-think base64 helper for shell work: encode a secret for a Kubernetes Secret manifest, decode a JWT payload's middle segment, or convert a tiny image into a `data:` URI. The standard primitive is `base64` (BSD on macOS, GNU on Linux) with subtle flag differences — this skill papers over those so the same invocation works everywhere.

Typical usage:

```
base64-codec encode <<< "hunter2"                       # standard alphabet
base64-codec encode --url-safe <<< "hunter2"            # RFC 4648 §5, '+' -> '-', '/' -> '_'
base64-codec encode --no-wrap < image.png > image.b64   # single line, useful for k8s
base64-codec decode "aHVudGVyMg=="                      # -> hunter2
base64-codec decode --url-safe "aHVudGVyMg"             # padding optional in URL-safe
```

The skill auto-detects whether the input is already base64 (regex on alphabet + length-mod-4) and warns when the user is about to double-encode something. Decode mode strips whitespace and `\n` before processing, so pasting from a clipboard with line wraps just works.

Do NOT use this skill for cryptographic encoding (base64 is NOT encryption — see `password:gen` for actual secrets), for hex/base32 (those are separate `xxd`/`base32` workflows), or for QR-encoding short strings (use `qr:make`). Related: `jwt:decode` for parsing tokens, `json:pretty` for inspecting decoded JSON payloads.
