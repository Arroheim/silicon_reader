# Silicon Reader

A native macOS (Apple Silicon) document reader in the spirit of
[SumatraPDF](https://github.com/sumatrapdfreader/sumatrapdf): fast, keyboard-driven,
no clutter. Swift + AppKit on top of the same engines Sumatra uses.

> Status: **phase 0** — project skeleton. Opens PDF and DjVu in a basic
> continuous-scroll window. The Sumatra-style UI is phase 1.

## 🚀 Quick start

```bash
git clone --recurse-submodules --shallow-submodules <repo-url> silicon_reader
cd silicon_reader
make run FILE=path/to/book.djvu
```

Only the Xcode **Command Line Tools** are required (`xcode-select --install`);
full Xcode is not needed.

## 🛠 Make targets

| Target | What it does |
|---|---|
| `make deps` | Fetches submodules and builds MuPDF as static libraries into `build/deps/mupdf` (~1 min, once) |
| `make build` | `swift build` (`CONFIG=release` for an optimized build) |
| `make test` | Unit tests (swift-testing) |
| `make e2e` | Builds the app and drives it end-to-end over its control socket (`Tests/E2ETests`) |
| `make lint` / `make format` | `swift format` check / rewrite |
| `make app` | Release build wrapped into an ad-hoc signed `build/SiliconReader.app` |
| `make smoke` | Opens sample PDF and DjVu in several view modes and saves window snapshots to `build/smoke/` |
| `make run FILE=…` | Builds the app and opens a document |

`SiliconReader -snapshot out.png [-actions viewFacing,zoomFitWidth] doc.pdf` runs the
given menu actions, saves the window to a PNG once all visible pages are drawn and
exits non-zero on failure. CI uses it as an end-to-end smoke check.
`SiliconReader -control /tmp/sr.sock doc.pdf` opens a debug control channel: one JSON
object per line (`{"cmd":"key","chars":"n"}`, `{"cmd":"find","text":"..."}`,
`{"cmd":"wait"}`, `{"cmd":"state"}` …, see `Sources/ReaderCore/Control/ControlProtocol.swift`).
The e2e tests use it to press keys through the real menu bar and key handling and
assert on reported state rather than pixels. Keep the socket path short (macOS limits
it to 104 bytes).

`-library path.json` points the app at a separate history/favorites file, so test
runs never touch your own (`~/Library/Application Support/SiliconReader/`).
Snapshot runs don't write per-file state or the session (each run starts the same);
`-persist YES` turns that back on, and `-snapshotAfter 3` delays the capture, e.g. to
change the open file and watch it reload. `-find text` searches before the capture,
`-palette text` opens the command palette (capture it with `-snapshotWindow palette`;
`properties` works the same) and `-printToPDF out.pdf` prints through the print path
into a file without any dialog.

## 🧱 Layout

```
Sources/
├── CMuPDF/          C facade over MuPDF (fz_try/fz_catch can't cross into Swift)
├── ReaderCore/      DocumentEngine protocol, MuPDF and DjVu engines — no AppKit
└── SiliconReader/   AppKit app
Vendor/
├── mupdf/           git submodule, pinned to a release tag
└── djvudec/         vendored single-file DjVu decoder
Tests/ReaderCoreTests/
```

## 📦 Dependencies

| Component | Version | License | How |
|---|---|---|---|
| [MuPDF](https://mupdf.com) | 1.28.5 | AGPL-3.0 | submodule, static link |
| [djvudec](https://github.com/kjk/djvudec) | `cfd3251` | MIT | vendored `djvu.c`/`djvu.h` |

Requirements: macOS 14+, Apple Silicon, Swift 6.

## ⚠️ Known toolchain quirk

With the Command Line Tools toolchain, `swift test` intermittently fails with
`plugin for module 'TestingMacros' not found`. `make test` loads the plugin
explicitly, so use it instead of bare `swift test`.

## 📄 License

[AGPL-3.0-or-later](LICENSE), as required by MuPDF.
