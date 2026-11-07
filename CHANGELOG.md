# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

To release: rename `[Unreleased]` to `[x.y.z] - YYYY-MM-DD`, commit, then
`make release VERSION=x.y.z` and `git push origin vx.y.z`. The release workflow
publishes the DMG with this section as the release notes.

## [Unreleased]

## [1.1.0] - 2026-11-07

### Added

- PDF annotations: highlight (`A`), underline (`U`), strike-out (`X`), notes (`T`) and
  freehand drawing (`D`), from the keyboard, the Annotate menu or a right click. Click
  an annotation to pick it, then `E` edits its note and `⌦` or `⌫` deletes it; hovering
  over a note shows its text. Annotations are ordinary PDF annotations, so other viewers
  see them too.
- Save Annotations (`⌥⌘S`) writes them into the open file; Save a Copy (`⌘S`) includes
  them. Closing, quitting or reloading with unsaved annotations asks first, and a file
  changed on disk no longer replaces them.

### Changed

- Selected text is the macOS selection blue instead of Sumatra's yellow, which couldn't
  be seen over a highlight.

### Fixed

- A drag starting just beside the text, such as left of a line or between lines, moved
  the page instead of selecting. It selects now, and the page moves when dragged from
  further away.
- Selecting text no longer moves the page while the pointer is away from the window's
  edges. Holding a selection at an edge scrolls that way, without moving the mouse, and
  the harder you pull, even against the edge of the screen, the faster it goes.
- Text inside a link can be selected: a drag selects it, a click still follows the link.

## [1.0.4] - 2026-11-07

Version 1.0.3 was tagged but never published: GitHub retired its macOS 14 runners
and the release stopped there. This release contains everything it had.

### Added

- Menus show single-key shortcuts such as `N`, `R` and `?`, so they can be found
  without the keyboard help. They still don't fire while typing in a text field.
- A page that can't be decoded shows "Couldn't display page N" instead of staying
  blank.

### Changed

- The manual test checklist moved to `docs/MANUAL_QA.md`.
- CI and releases test the built app on macOS 15, the oldest macOS GitHub still
  offers. The app still targets macOS 14, but isn't run on it before a release.

## [1.0.2] - 2026-10-21

### Added

- Find Previous / Find Next arrows next to the toolbar's search field; they search
  for the field's text, so Return isn't needed first.

### Fixed

- Choosing a zoom level from the toolbar's drop-down list had no effect.
- While the page, zoom or search box had the focus, the toolbar buttons that act on
  the page (zoom out, fit, rotate) were disabled until you clicked the page.

### Changed

- Dark mode: the background around pages is the system's dark gray instead of
  pure black.
- New windows are 1100 points wide (was 1000), so the whole toolbar, search field
  included, fits next to the sidebar.
- New screenshots in the README.

## [1.0.1] - 2026-10-21

### Fixed

- macOS 26 and later: pages no longer slide under the toolbar and cover the window
  title (the new Liquid Glass toolbar floats over the content). The canvas now
  starts below the toolbar on every macOS version.

### Changed

- Every build is tested on macOS 14 too: CI and the release workflow run the
  smoke and end-to-end tests of the very app that goes into the DMG on a macOS 14
  runner, and the release is published only if they pass.
- Local builds record the real SDK, so they look the same as the published app;
  `make app` checks that the app still targets macOS 14 and links only system
  libraries.
- New README screenshots.

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
