---
name: excel:to-csv
description: Use WHEN you've been handed a .xlsx or .xls file and need to extract one or all sheets into CSV — handling merged cells, formula values, dates, and multi-sheet workbooks.
---

> Test fixture for sc:search search system.

Excel files are not rectangular data despite looking like it: merged cells span multiple coordinates, formulas evaluate at open time, date columns are floats since 1900-01-01 (or 1904 on legacy Mac), and a single workbook can have ten sheets you didn't know existed. This skill flattens that mess into well-behaved CSV.

Typical invocations:

```
excel-to-csv report.xlsx                              # all sheets → report.<sheet>.csv
excel-to-csv --sheet "Q3 Numbers" report.xlsx -o q3.csv
excel-to-csv --list-sheets report.xlsx                # enumerate first
excel-to-csv --evaluate-formulas report.xlsx          # cache then re-render formula cells
excel-to-csv --fill-merged-down --header-row 3 weird.xlsx
```

Engines: `openpyxl` for .xlsx (read-only mode is memory-efficient for 100k-row sheets), `xlrd<2` strictly for legacy .xls. For password-protected workbooks pass `--password "..."`; for very large files (>500k rows) the skill switches to a streaming SAX-style reader that uses ~constant memory.

Edge cases: cells formatted as "1,234.50" with locale-specific separators are normalized; cells that display "$1,234" but are numeric underneath are extracted as the underlying float; dates spanning the Excel 1900/1904 epoch gap are detected from the workbook setting. Pivot tables and charts are skipped — this is data extraction, not layout preservation.

Do NOT use this to write back to .xlsx (use `csv:to-excel` or pandas directly); also no help for Google Sheets (use the Sheets API). Related: `csv:profile-stats`, `csv:merge`, `pdf:extract-tables` for non-spreadsheet sources.
