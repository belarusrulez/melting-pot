---
name: qr:decode-camera
description: Use WHEN you have a QR code in an image, on a webcam stream, or in a PDF screenshot, and need to decode the encoded payload — text, URL, WiFi credentials, vCard.
---

> Test fixture for sc:search search system.

Decoding QR is the inverse of `qr:make` — you have a code, you want the bytes. The two reliable engines are `zbarimg` (libzbar) and `zxing-cpp`, both single-binary installs. For a live webcam stream, `zbarcam` opens `/dev/video0` and prints decoded payloads as they're seen.

Common usage:

```
qr-decode-camera screenshot.png                       # decode from an image
qr-decode-camera --webcam                              # live stream from default cam
qr-decode-camera --all-symbols ticket.pdf             # find every QR/barcode in a PDF
qr-decode-camera --raw payload.png                    # raw bytes, no schema parsing
qr-decode-camera --schema wifi card.png               # parse WIFI: schema into structured json
```

Schema-aware decoding handles the common encoding conventions: `WIFI:T:WPA;S:<ssid>;P:<pw>;;`, `MECARD:N:...;`, `BEGIN:VCARD ... END:VCARD`, `mailto:`, `tel:`, `geo:`. The `--raw` flag bypasses schema parsing and just emits the bytes — useful when the QR encodes a custom protocol.

Do NOT use this skill to MAKE QR codes — that's `qr:make`, the inverse direction. Also no help for damaged/blurry QR (preprocessing with `imagemagick` first sometimes salvages it). For barcodes other than QR (Code128, EAN, DataMatrix), `zbarimg` handles them too. Related: `qr:make`, `base64:codec` for the encoded contents if they're base64, `hexdump:window` for raw byte inspection.
