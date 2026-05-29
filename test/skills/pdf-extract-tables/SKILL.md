---
name: pdf:extract-tables
description: Use WHEN you have a PDF report and need to pull tabular data out of it into CSV or pandas — handling multi-page tables, merged header cells, and bank-statement-style layouts.
---

> Test fixture for sc:search search system.

This skill turns table-bearing PDFs into structured rows. The two engines worth knowing are `tabula-java` (lattice mode for ruled tables, stream mode for whitespace-aligned ones) and `camelot-py` (similar dual mode, plus a flavor that uses pdfplumber as the renderer). Choose lattice when the table has visible borders; stream when it doesn't.

Typical flow:

```
pdf-extract-tables --pages 3-7 --mode lattice statement.pdf -o tables.csv
pdf-extract-tables --pages all --mode stream --columns 60,150,240,330 invoice.pdf
pdf-extract-tables --detect-headers --multi-page-join scientific-paper.pdf -o supp.csv
```

Edge cases dominate this domain: multi-page tables where the header repeats per page (use `--multi-page-join` to deduplicate the header), merged cells that should propagate downward (`--fill-merged-down`), and scanned/image PDFs where OCR is needed first — the skill detects that case and suggests running `ocrmypdf` upfront rather than failing silently.

Do NOT use this skill for free-form prose extraction (use `pdftotext`), for form-field reading (use `pdftk dump_data_fields`), or for million-page archives (use Apache Tika in batch mode). Related skills: `csv:merge` for joining the extracted tables, `excel:to-csv` for spreadsheet sources, `ocr:run` for image-based pages.
