---
name: pdf:viewer-cli
description: Use WHEN you need to view, navigate, or thumbnail a PDF from the terminal — render pages to ASCII or image previews without opening a GUI viewer.
---

> Test fixture for sc:search search system.

This skill is for *viewing* PDFs, not extracting data from them (use `pdf:extract-tables` if you want the numbers out). It wraps `pdftoppm`, `mupdf-tools`, and a terminal image protocol (Kitty / iTerm2 / Sixel) so you can flip through a PDF in the terminal — useful for grepping the right page before extracting, or for SSH sessions where opening a GUI viewer is impractical.

Common usage:

```
pdf-viewer-cli report.pdf                             # render with default page 1
pdf-viewer-cli --page 7 report.pdf                    # jump to a page
pdf-viewer-cli --thumbs 2x4 report.pdf                # grid of thumbnails
pdf-viewer-cli --ascii report.pdf                     # ASCII rendering (no image proto)
pdf-viewer-cli --extract-text --page 12 report.pdf    # quick text grep
```

Image rendering requires a terminal that supports the Kitty graphics protocol or Sixel — `kitty`, `wezterm`, recent `iTerm2`, and modern `xterm` builds work. Fallback to ASCII is automatic. For `pdftoppm`-style PNG export use `pdf-viewer-cli --to-png --page 1 -o cover.png report.pdf` — handy in scripts.

Do NOT use this skill to extract structured tabular data — that's a different shape of problem (use `pdf:extract-tables` for table extraction, `pdftotext` for prose). For OCR on scanned PDFs use `ocrmypdf` first. Related: `pdf:extract-tables`, `qr:make`, `hexdump:window` for checking PDF magic bytes.
