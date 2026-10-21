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
      (rendering itself is covered by `make check-library`, see below)
- [ ] Corrupted / truncated files: no crash, a readable error
- [ ] Tab switching with ⌘} / ⌘{ (e2e only checks the wiring: NSWindow enables
      these actions only in the key window, which a background test run doesn't get)
- [ ] Session restore with several windows and tabs (check the small scroll offset
      seen after restoring two tabs in phase 1)

### Release-blocking gaps

- [x] **Open Recent** menu (File ▸ Open Recent), built from the history; Clear Menu
      keeps per-file state and favorites
- [x] **Drag and drop** documents onto a window (they open as tabs); the Dock icon
      takes them through the declared document types
- [x] **Settings window** (⌘,): default zoom and layout, remember state per document,
      restore session, reload on change — stored in the library file
- [x] **Page thumbnails** in the sidebar (⌥⌘2; bookmarks ⌥⌘3), following the current page
- [ ] Single-key shortcuts visible in menus (today only in the `?` help and tooltips)
- [ ] Manual check: drop a file from Finder on a window and on the Dock icon (e2e
      drives the drop handler, not a real drag session)

### Packaging

- [x] Version from one place: the git tag (or `VERSION=`) is written into the bundled
      `Info.plist` by `make app`, build number = commit count
- [x] About box: author (Stanislav Seredkin aka Itterheim aka Arronax, e-mail), repository link, MuPDF / djvudec / SumatraPDF credits
- [x] `make dmg`: DMG with the app and an Applications link, plus a `.sha256`
- [ ] Signing: ad-hoc today. Developer ID signing + notarization needs an Apple
      Developer account — decide before publishing binaries
- [x] README.md + README.ru.md in the tgbookhunter style (badges, sections, tables),
      screenshots, keyboard reference
- [x] CHANGELOG.md (Keep a Changelog; the release notes are cut from it)
- [x] Source artwork moved to `docs/assets/icon-source-v*.png`, screenshots next to it
- [x] Release workflow: a `v*` tag runs lint/test/e2e, builds the DMG and publishes a
      GitHub release (`make release VERSION=x.y.z`, then push the tag)
- [x] GitHub repo: https://github.com/Arroheim/silicon_reader (public; first CI run green)
- [x] CHANGELOG.md has its `[1.0.0]` section
- [x] Released 1.0.0: https://github.com/Arroheim/silicon_reader/releases/tag/v1.0.0

### Library check

`make check-library DIR=… [ALL_PAGES=1]` runs `reader-check` over a folder: one
process per file, so a crash or hang is reported instead of stopping the run.

- [x] 1 332 real books (PDF + DjVu): first, middle and last page of each — found the
      djvudec bug below
- [x] Fixed: djvudec truncated INCL component ids to 63 bytes, so pages sharing a JB2
      dictionary failed to render (`Vendor/djvudec/PATCHES.md`)
- [ ] Regression fixture: a small DjVu whose INCL id is longer than 63 bytes
- [ ] Report the INCL bug upstream to kjk/djvudec
- [x] Every page of the same library (`ALL_PAGES=1`): 514 088 pages, 0 crashes, 0 hangs;
      the one failure (page 35 of "Введение в теорию чисел", 1984.djvu) is corrupt JB2 data —
      DjVuLibre's `ddjvu` fails on it too
- [ ] A page that fails to decode: show a readable placeholder in the canvas (check
      what it looks like today), like Sumatra does
- [ ] Peak memory 749 MB while sweeping a whole book in one process — fine for a checker,
      but worth a look together with the `TextStore` cache bound below

## Gap to SumatraPDF for PDF/DjVu

What Sumatra does with PDF/DjVu that Silicon Reader doesn't (yet). Ordered by
expected value for everyday reading.

| Feature | Sumatra | Notes |
|---|---|---|
| Annotations: highlight, underline, strike-out, notes, freehand | `a`/`u` keys, edit panel, save | MuPDF can create and save them (`pdf_*` annotation API) |
| PDF forms: fill, save | partial | MuPDF widgets API |
| SyncTeX forward/inverse search | yes | for LaTeX users; needs a CLI entry point and editor command setting |
| Advanced settings | `SumatraPDF-settings.txt` | 1.0 has the essentials in Settings (⌘,) |
| Themes beyond system light/dark | ~20 themes | theme = colors for chrome + canvas |
| Rectangle selection → copy as image | Ctrl+drag | |
| Keyboard text selection, keyboard link following | F7, Shift+F | |
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
