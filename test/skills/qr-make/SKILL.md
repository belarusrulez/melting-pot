---
name: qr:make
description: Encode text, URLs, or WiFi credentials as a QR code rendered inline in the terminal as ASCII blocks or saved as a PNG/SVG file.
---

> Test fixture for sc:search search system.

Trigger when a user wants to "share this URL to my phone", "show a WiFi QR for guests", "make a vCard barcode", or generally encode short text into a scannable image. The two workhorse CLIs are `qrencode` (libqrencode) and `qr` (a thin Python wrapper); either is usually one package install away.

Terminal rendering: `qrencode -t ANSIUTF8 "https://example.com"` prints crisp half-block characters that scan reliably from a dark-themed terminal. For light themes use `-t ANSI` to invert, and always include a quiet zone — `qrencode` does this by default, but tmux or zellij may clip the rightmost column, so add `-m 2` to widen the margin.

File output: `qrencode -o out.png -s 8 -m 2 "payload"` produces an 8-pixels-per-module PNG; swap `-o` for `-t SVG` if the user needs vector. For very long payloads, raise the error-correction level with `-l L` (lower correction, more capacity) only when the QR will be scanned at close range.

Edge cases: WiFi QR uses the schema `WIFI:T:WPA;S:<ssid>;P:<password>;;`; vCard payloads must end with `\nEND:VCARD\n`. URLs longer than ~300 chars produce dense codes that fail on phone cameras — shorten first.
