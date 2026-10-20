# Silicon Reader — roadmap

Phase 1 (PDF + DjVu with SumatraPDF's core reading features) is done: engines,
canvas and layouts, window chrome, keyboard map, text and search, per-file state
and sessions, print/properties/command palette, e2e tests over the control channel.

This file lists what is left: the **1.0 release**, then feature phases ordered by
how much they close the gap to SumatraPDF. Every item that changes behavior ships
with unit and/or e2e tests (`make test`, `make e2e`).

## 1.0 — release

1.0 means: a PDF/DjVu reader you can hand to someone, with no known crashes and the
reading workflow of SumatraPDF. It is **not** feature parity with Sumatra (see the
gap list below).

### Manual QA pass (things the automated tests cannot drive)

The control channel exercises commands and state, not the mouse, gestures or
system dialogs. The home-page Open crash (fixed in 1.0) lived exactly there.

- [ ] Mouse: drag-select across pages, hand-pan on empty areas, double/triple click
- [ ] Links: click internal and external links in PDFs; cursor shapes over links/text
- [ ] Trackpad: pinch zoom around the pointer, smart magnify, ⌘-scroll zoom
- [ ] Wheel/trackpad flipping pages in non-continuous mode
- [ ] Open dialog, Finder "Open With", drag a file onto the Dock icon
- [ ] Tabs: open several files, drag tabs out/in, ⇧⌘[ / ⇧⌘], close the last tab → home
- [ ] Password-protected PDF: prompt, wrong password, cancel
- [ ] Print to a real printer and the print preview; landscape pages
- [ ] Full screen and presentation mode (enter/leave animations, Esc, clicks)
- [ ] Two displays with different scale factors; moving a window between them
- [ ] Live switch between light and dark appearance
- [ ] Large documents: 1000+ page PDF, heavy scanned DjVu — scroll speed, memory
- [ ] Corrupted / truncated files: no crash, a readable error
- [ ] Session restore with several windows and tabs (check the small scroll offset
      seen after restoring two tabs in phase 1)

### Release-blocking gaps

- [ ] **Open Recent** menu (File ▸ Open Recent) — history exists, the menu doesn't
- [ ] **Drag and drop** a document onto a window / the Dock icon
- [ ] **Settings window** (⌘,) with the essentials: default zoom and layout,
      remember state per document on/off, restore session on/off, reload on change
- [ ] Single-key shortcuts visible in menus (today only in the `?` help and tooltips)

### Packaging

- [ ] Version 1.0.0 from one place (`Info.plist` ← Makefile `VERSION`), shown in About
- [ ] About box: credits for MuPDF (AGPL-3.0), djvudec (MIT), fixtures (GPL)
- [ ] `make dmg`: DMG with the app and an Applications link
- [ ] Signing: ad-hoc today. Developer ID signing + notarization needs an Apple
      Developer account — decide before publishing binaries
- [ ] README.md + README.ru.md in the tgbookhunter style (badges, sections, tables),
      screenshots, keyboard reference
- [ ] CHANGELOG.md
- [ ] Move `Sicon.png` / `Siicon2.png` (source artwork) into `Resources/` or out of the repo
- [ ] CI: build the DMG on tags, attach it to a GitHub release; tag `v1.0.0`

## Gap to SumatraPDF for PDF/DjVu

What Sumatra does with PDF/DjVu that Silicon Reader doesn't (yet). Ordered by
expected value for everyday reading.

| Feature | Sumatra | Notes |
|---|---|---|
| Annotations: highlight, underline, strike-out, notes, freehand | `a`/`u` keys, edit panel, save | MuPDF can create and save them (`pdf_*` annotation API) |
| PDF forms: fill, save | partial | MuPDF widgets API |
| SyncTeX forward/inverse search | yes | for LaTeX users; needs a CLI entry point and editor command setting |
| Settings and advanced settings file | Options dialog + `SumatraPDF-settings.txt` | see 1.0 for the essentials |
| Themes beyond system light/dark | ~20 themes | theme = colors for chrome + canvas |
| Rectangle selection → copy as image | Ctrl+drag | |
| Keyboard text selection, keyboard link following | F7, Shift+F | |
| Page thumbnails | sidebar / `&` navigation | |
| Read Aloud | toolbar button | AVSpeechSynthesizer |
| Favorites of all files in the sidebar | yes | we show the current file's |
| Fonts list in Properties | yes | MuPDF can enumerate fonts |
| Custom keyboard shortcuts | via settings | the command table makes this cheap |
| Localization | ~60 languages | start with en + ru |
| External viewers / "Open in…" | yes | |

## Phase 2 — more formats

SumatraPDF's other engines: `EngineMupdf` (XPS, EPUB, FB2, MOBI, CBZ),
`EngineEbook`, `EngineImages`, `EnginePs`, `EngineDvi`, plus CHM and Markdown.

- [ ] Formats MuPDF already opens: XPS/OXPS, CBZ, SVG, single images
      (PNG, JPEG, TIFF incl. multi-page) — extend `DocumentFormat`, UTIs in
      `Info.plist`, fixtures and engine tests per format
- [ ] Reflowable ebooks (EPUB, MOBI, FB2, HTML): MuPDF layout with font size and
      page size from the window (Sumatra's EbookUI settings); re-layout on resize
      keeping the reading position
- [ ] Comic archives CBR / CB7 / CBT via libarchive. macOS ships the library
      (`libarchive.tbd`) but not its headers → vendor the headers or the library;
      image-collection engine, manga mode (right-to-left), lazy page sizes
- [ ] Folder of images as a comic
- [ ] PostScript / EPS (Sumatra uses Ghostscript) — likely skip (licensing, size)
- [ ] DVI, CHM — likely skip

## Engineering

- [ ] Split `DocumentView` (~900 lines): drawing/tiles, navigation, input
- [ ] Bound memory: `TextStore` and link caches grow with every page visited
- [ ] Group debug flags (`-snapshot`, `-control`, `-actions`, …) into one `DebugOptions`
- [ ] Accessibility: expose the text layer to VoiceOver
- [ ] Rendering benchmarks (first page time, scroll throughput) tracked in CI
- [ ] Robustness corpus: run open/render/text over damaged PDFs/DjVu (djvudec ships a
      fuzz corpus) in a nightly job
- [ ] Drop the swift-testing plugin workaround in the Makefile once the Command Line
      Tools toolchain loads `TestingMacros` reliably
