# Test fixtures

| File | Source | License |
|---|---|---|
| `lizard2002.djvu` | [djvulibre/doc/lizard2002.djvu](https://github.com/barak/djvulibre/blob/master/doc/lizard2002.djvu) | GPL-2.0-or-later (DjVuLibre) |
| `sumatra-test.djvu` | [sumatrapdf/docs/test/test.djvu](https://github.com/sumatrapdfreader/sumatrapdf/blob/master/docs/test/test.djvu) — single page, no text layer | GPL-3.0 (SumatraPDF) |
| `djvu2spec.djvu` | [djvulibre/doc/djvu2spec.djvu](https://github.com/barak/djvulibre/blob/master/doc/djvu2spec.djvu) — 39 pages, outline, text layer | GPL-2.0-or-later (DjVuLibre) |

PDF fixtures are generated at test time with Core Graphics (see `TestPDF.swift`),
so their content is known exactly and no binary PDFs live in the repo.
