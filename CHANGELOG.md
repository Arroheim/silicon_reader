# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

To release: rename `[Unreleased]` to `[x.y.z] - YYYY-MM-DD`, commit, then
`make release VERSION=x.y.z` and `git push origin vx.y.z`. The release workflow
publishes the DMG with this section as the release notes.

## [Unreleased]

## [1.0.0] - 2026-10-21

### Added

- Settings window (⌘,): default layout and zoom, remember each document's view,
  restore the session, reload changed files.
- File ▸ Open Recent, built from the reading history, with Clear Menu.
- Drag and drop: documents dropped on a window open as tabs.
- Page thumbnails in the sidebar (⌥⌘2), next to bookmarks (⌥⌘3); they follow
  the current page and navigate on click.
- About Silicon Reader with the author and credits.
- PDF (MuPDF 1.28) and DjVu (djvudec) engines: rendering, text layer, outline,
  links, page labels, document properties, password-protected PDFs.
- SumatraPDF's layouts: single page, facing, book view, each continuous or paged;
  fit page / width / height / content, shrink to fit, actual size and Sumatra's
  zoom steps (8.33 %–6400 %), rotation, presentation and full screen modes.
- Background tiled rendering with low-resolution previews, Retina aware.
- Window chrome after SumatraPDF: toolbar with page box and zoom box, native tabs,
  sidebar with bookmarks (table of contents) and favorites, home page with
  "Frequently Read" thumbnails.
- SumatraPDF's keyboard map adapted to macOS, from one command table that also
  drives the menus and the keyboard help (`?`).
- Text selection (drag, double/triple click), copy, select all, zoom to selection,
  link following, hand panning.
- Find with match case, next/previous (⌘G / ⇧⌘G, F3), highlights for all matches
  on screen.
- Back/forward history, next/previous file in folder, reopen last closed,
  duplicate in new window, save a copy.
- Per-document view state, session restore, automatic reload when a file changes
  on disk (including atomic saves).
- Printing (300 dpi, auto-rotation), Document Properties (⌘I), command palette
  (⌘K) with Sumatra's prefixes `>` `@` `#` `$` `%`.
- Invert colors, page info and cursor position overlays, auto scroll.
- Developer tooling: unit tests, end-to-end tests over a debug control channel,
  window snapshots for smoke tests, `reader-check` to batch-check a document
  library, DMG packaging and a tag-driven release workflow.

### Fixed

- DjVu: pages sharing a JB2 dictionary failed to render when the dictionary's
  component name was longer than 63 bytes (common with Cyrillic file names).
  Patched in the vendored djvudec, see `Vendor/djvudec/PATCHES.md`.
- Opening a document from the home page crashed (infinite recursion through the
  responder chain).
