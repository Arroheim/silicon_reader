import Foundation
import ReaderCore
import Testing

/// End-to-end checks against the built app (`make e2e`). Each test launches
/// its own instance; they run one at a time to keep the machine responsive.
@Suite("Reader end-to-end", .serialized)
struct ReaderE2ETests {
    // MARK: - Opening and navigation

    @Test("opens a DjVu at the first page in Sumatra's default view")
    func opensDocument() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }

        let state = try app.waitUntilSettled()

        #expect(state.document == Documents.spec.path)
        #expect(state.pageCount == 39)
        #expect(state.page == 0)
        #expect(state.zoom == .fitPage)
        #expect(state.mode == ViewMode(arrangement: .single, continuous: true))
        #expect(state.sidebarVisible, "the document has an outline")
    }

    @Test("pages with n/p, Home/End and ⌘↑/⌘↓")
    func pageKeys() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press("n").page == 1)
        #expect(try app.press("n").page == 2)
        #expect(try app.press("p").page == 1)
        #expect(try app.press("end").page == 38)
        #expect(try app.press("home").page == 0)
        #expect(try app.press("down", "cmd").page == 38, "⌘↓ goes through the menu bar")
        #expect(try app.press("up", "cmd").page == 0)
    }

    @Test("Back and Forward undo jumps")
    func history() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        try app.press("end")
        #expect(try app.press("backspace").page == 0)
        #expect(try app.press("backspace", "shift").page == 38)
        #expect(try app.press("[", "cmd").page == 0, "⌘[ is Back too")
    }

    // MARK: - Zoom and layout

    @Test("zoom shortcuts follow SumatraPDF")
    func zoom() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press("2", "cmd").zoom == .fitWidth)
        let widthPercent = try app.state().zoomPercent
        let zoomedIn = try app.press("+", "cmd")
        #expect(zoomedIn.zoomPercent > widthPercent)
        #expect(zoomedIn.zoom?.isFit == false, "a zoom step leaves fit modes")
        #expect(try app.press("0", "cmd").zoom == .percent(100))
        #expect(try app.press("z").zoom == .fitPage, "Z from an absolute zoom goes to fit page")
        #expect(try app.press("z").zoom == .fitWidth)
    }

    @Test("layout and rotation shortcuts")
    func layout() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press("7", "cmd").mode?.arrangement == .facing)
        #expect(try app.press("8", "cmd").mode?.arrangement == .book)
        #expect(try app.press("c").mode?.continuous == false)
        #expect(try app.press("6", "cmd").mode == ViewMode(arrangement: .single, continuous: false))
        #expect(try app.press("]").rotation == 90)
        #expect(try app.press("r", "cmd").rotation == 180)
        #expect(try app.press("[").rotation == 90)
    }

    @Test("invert colors and presentation mode toggle, Esc leaves presentation")
    func viewModes() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press("I").invertsColors)
        let presenting = try app.press("f", "cmd", "shift")
        #expect(presenting.presenting)
        #expect(presenting.mode == ViewMode(arrangement: .single, continuous: false))
        #expect(presenting.zoom == .fitPage)
        let back = try app.press("escape")
        #expect(!back.presenting)
        #expect(back.mode == ViewMode(arrangement: .single, continuous: true), "previous layout is restored")
    }

    @Test("unbound keys are reported as not handled")
    func unboundKey() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let response = try app.send(ControlRequest(.key, chars: "x"))
        #expect(response.handled == false)
        #expect(response.state?.page == 0)
    }

    // MARK: - Text

    @Test("finds text across pages and steps through matches")
    func find() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        try app.send(ControlRequest(.find, text: "WAVELET"))
        let first = try app.waitUntilSettled()
        let firstMatch = try #require(first.match, "case-insensitive by default")
        #expect(first.selectedText.lowercased() == "wavelet")
        #expect(first.page == firstMatch.page)

        let next = try app.press("g", "cmd")
        let nextMatch = try #require(next.match)
        #expect((nextMatch.page, nextMatch.start) > (firstMatch.page, firstMatch.start))

        #expect(try app.press("g", "cmd", "shift").match == firstMatch, "⇧⌘G goes back")
        #expect(try app.press("f3").match == nextMatch, "F3 is Find Next too")
    }

    @Test("reports when nothing matches")
    func findNothing() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        try app.send(ControlRequest(.find, text: "zzqqxx"))
        let state = try app.waitUntilSettled()

        #expect(state.match == nil)
        #expect(state.subtitle.contains("No matches"))
    }

    @Test("selection yields the text under it")
    func selection() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let state = try app.send(ControlRequest(.select, page: 0, start: 0, end: 16)).state

        #expect(state?.selectedText == "SPECIFICATION OF")
        #expect(try app.press("escape").selectedText == "", "Esc clears the selection")
    }

    @Test("PDFs open and search the same way")
    func pdf() throws {
        let app = try AppSession(documents: [Documents.pdf])
        defer { try? app.quit() }
        #expect(try app.waitUntilSettled().pageCount == 60)

        try app.send(ControlRequest(.find, text: "profile"))
        let state = try app.waitUntilSettled()

        #expect(state.match != nil)
        #expect(state.selectedText.lowercased() == "profile")
    }

    // MARK: - Files

    @Test("opens the next and previous file in the folder in the same tab")
    func folderNavigation() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let next = try app.press("right", "cmd", "shift")
        #expect(next.document == Documents.lizard.path)
        #expect(next.openDocuments == [Documents.lizard.path], "replaced, not a new tab")
        #expect(try app.press("left", "cmd", "shift").document == Documents.spec.path)
    }

    @Test("reloads the document when its file is replaced on disk")
    func reloadOnChange() throws {
        let dir = AppSession.temporaryDirectory()
        let watched = dir.appendingPathComponent("watched.djvu")
        try FileManager.default.copyItem(at: Documents.spec, to: watched)
        let app = try AppSession(documents: [watched])
        defer { try? app.quit() }
        #expect(try app.waitUntilSettled().pageCount == 39)

        // Save the way editors do: write elsewhere, then rename over the file.
        let replacement = dir.appendingPathComponent("replacement.tmp")
        try FileManager.default.copyItem(at: Documents.lizard, to: replacement)
        _ = try FileManager.default.replaceItemAt(watched, withItemAt: replacement)

        let state = try app.waitFor { $0.pageCount == 2 }
        #expect(state.pageCount == 2)
        #expect(state.subtitle.contains("Reloaded"))
    }

    @Test("remembers page and layout per file across launches")
    func perFileState() throws {
        let library = AppSession.temporaryDirectory().appendingPathComponent("library.json")

        let first = try AppSession(documents: [Documents.spec], library: library, persist: true)
        try first.waitUntilSettled()
        try first.press("7", "cmd")
        try first.press("n")
        let left = try first.press("n")
        try first.quit()

        let second = try AppSession(documents: [Documents.spec], library: library, persist: true)
        defer { try? second.quit() }
        let restored = try second.waitUntilSettled()

        #expect(restored.mode?.arrangement == .facing)
        #expect(restored.page == left.page)
    }

    @Test("restores the session's documents when launched without files")
    func sessionRestore() throws {
        let library = AppSession.temporaryDirectory().appendingPathComponent("library.json")

        let first = try AppSession(documents: [Documents.spec, Documents.pdf], library: library, persist: true)
        try first.waitUntilSettled()
        try first.quit()

        let second = try AppSession(library: library, persist: true)
        defer { try? second.quit() }
        let state = try second.waitUntilSettled()

        #expect(Set(state.openDocuments) == [Documents.spec.path, Documents.pdf.path])
    }

    /// Regression: the home page's own `openDocument(_:)` re-sent the action
    /// to the responder chain, found itself again and recursed until the
    /// stack overflowed (crash on "Open a document…" and the toolbar's Open).
    @Test("Open… from the home page opens the chosen file instead of crashing", arguments: ["action", "shortcut"])
    func openFromHome(via: String) throws {
        let app = try AppSession(extraArguments: ["-openPanelResult", Documents.spec.path])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        if via == "action" {
            #expect(try app.send(ControlRequest(.action, name: "openDocument")).handled == true)
        } else {
            try app.press("o", "cmd")
        }
        let state = try app.waitUntilSettled()

        #expect(state.document == Documents.spec.path, "the home page is replaced by the document")
        #expect(state.openDocuments == [Documents.spec.path])
    }

    /// Guards the cause of the crash above: an app-level action must reach the
    /// app delegate from any window's focus. A same-named method anywhere in the
    /// chain (view controllers, views) shadows it — and if it forwards the
    /// action to nil, it recurses as soon as its window is key.
    @Test(
        "app-level actions reach the app delegate from any window",
        arguments: ["openDocument", "newWindow", "reopenLastClosed", "showKeyboardHelp"])
    func appActionsNotShadowed(action: String) throws {
        let home = try AppSession()
        defer { try? home.quit() }
        try home.waitUntilSettled()
        #expect(try home.send(ControlRequest(.resolve, name: action)).target == "AppDelegate", "from the home page")

        let document = try AppSession(documents: [Documents.spec])
        defer { try? document.quit() }
        try document.waitUntilSettled()
        #expect(try document.send(ControlRequest(.resolve, name: action)).target == "AppDelegate", "from a document")
    }

    @Test("starts on the home page without a session")
    func homePage() throws {
        let app = try AppSession()
        defer { try? app.quit() }

        let state = try app.waitUntilSettled()

        #expect(state.document == nil)
        #expect(state.openDocuments.isEmpty)
    }
}
