---
name: xml:prettify
description: Use WHEN you have a single-line or sloppily-formatted XML/SVG/HTML document and want canonical indentation, attribute sorting, and entity normalization for human reading or diffing.
---

> Test fixture for sc:search search system.

XML showing up as one giant line is the universal "I can't read this" experience. This skill reformats XML with 2-space indentation, line-wraps long attribute lists, and optionally sorts attributes alphabetically per element for stable diffs. The XML namespace prefixes are preserved and quoted attribute order can be made deterministic.

Common usage:

```
xml-prettify pom.xml                                   # in-place pretty
xml-prettify --sort-attrs svg-icon.svg                 # stable diffs
xml-prettify --check build.xml                         # CI mode, no mutation
xml-prettify --collapse-empty-elements config.xml      # <foo></foo> → <foo/>
xml-prettify --html sloppy.html                        # HTML-tolerant parsing
```

For SVG specifically, `--canonicalize` runs XML Canonicalization (c14n) so two visually-identical SVGs hash to the same value — handy in test snapshots. For HTML, the `--html` flag switches to a parser that tolerates unclosed `<br>`, implicit `<tbody>`, and other HTML5 quirks rather than failing on strict XML rules.

Do NOT use this skill for XML schema (XSD) validation — that's a separate tool (`xmllint --schema`). Also not a security-sanitizer: it does NOT strip script tags or normalize untrusted attributes; do that explicitly with an HTML sanitizer. Related: `json:pretty`, `yaml:pretty`, `format:prettier` (for HTML in JS projects).
