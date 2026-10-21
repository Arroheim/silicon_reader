import Foundation
import ReaderCore
import Testing

/// Many documents at once: tabs, switching, closing, reopening.
/// An extension of the serialized suite so it never runs alongside other app instances.
extension ReaderE2ETests {
    /// `count` distinct files (copies of the fixtures) so none is de-duplicated as "already open".
    private func documentCopies(_ count: Int) throws -> [URL] {
        let dir = AppSession.temporaryDirectory()
        let sources = [Documents.spec, Documents.lizard, Documents.pdf]
        return try (0..<count).map { i in
            let source = sources[i % sources.count]
            let copy = dir.appendingPathComponent(String(format: "doc%02d.%@", i, source.pathExtension))
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        }
    }

    @Test("opens a batch of documents as tabs of one window")
    func batchOfTabs() throws {
        let files = try documentCopies(12)
        let app = try AppSession(documents: files)
        defer { try? app.quit() }

        let state = try app.waitUntilSettled(timeout: 30)

        #expect(state.windowCount == 1, "all documents share one window")
        #expect(Set(state.frontTabs) == Set(files.map(\.path)))
        #expect(state.frontTabs.count == 12)
        #expect(state.document != nil && state.pageCount > 0, "the selected tab shows its document")
    }

    @Test("opening a file that is already open selects its tab")
    func reopenSelects() throws {
        let files = try documentCopies(3)
        let app = try AppSession(documents: files)
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let response = try app.send(ControlRequest(.open, path: files[0].path))
        let state = try app.waitUntilSettled()

        #expect(response.handled == true)
        #expect(state.frontTabs.count == 3, "no duplicate tab")
        #expect(state.document == files[0].path)
    }

    /// Switching itself is AppKit's and only allowed in the key window, which an
    /// app launched by the tests never is (see TODO.md, manual QA). What we own
    /// is the wiring: the shortcuts exist and reach the window's tab actions.
    @Test(
        "⇧⌘] and ⇧⌘[ are bound to the window's next/previous tab",
        arguments: [("}", "selectNextTab:"), ("{", "selectPreviousTab:")])
    func tabShortcuts(key: String, action: String) throws {
        let files = try documentCopies(3)
        let app = try AppSession(documents: files)
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let menu = try app.send(ControlRequest(.resolve, chars: key, modifiers: ["cmd"]))
        #expect(menu.target == action, "menu item for ⌘\(key)")

        let name = String(action.dropLast())
        // ReaderWindow inherits the tab actions from NSWindow.
        #expect(try app.send(ControlRequest(.resolve, name: name)).target == "ReaderWindow")
    }

    @Test("closing tabs keeps the rest; Reopen Last Closed brings one back")
    func closeAndReopen() throws {
        let files = try documentCopies(3)
        let app = try AppSession(documents: files)
        defer { try? app.quit() }
        let before = try app.waitUntilSettled()
        let closed = try #require(before.document)

        try app.press("w", "cmd")
        let after = try app.waitUntilSettled()
        #expect(after.frontTabs.count == 2)
        #expect(!after.openDocuments.contains(closed))

        let reopened = try app.press("t", "cmd", "shift")
        #expect(reopened.openDocuments.contains(closed))
        #expect(Set(reopened.openDocuments) == Set(files.map(\.path)))
    }

    @Test("closing the last document tab shows the home page instead of closing the window")
    func closeLastTab() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let state = try app.press("w", "cmd")

        #expect(state.document == nil)
        #expect(state.windowCount == 1)
    }
}
