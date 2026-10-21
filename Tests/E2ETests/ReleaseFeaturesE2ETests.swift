import Foundation
import ReaderCore
import Testing

/// Settings, Open Recent, drag and drop, page thumbnails and About.
/// An extension of the serialized suite, so these never run alongside the others.
extension ReaderE2ETests {
    /// A throwaway library file prepared before launch.
    private static func library(_ prepare: (Library) -> Void = { _ in }) -> URL {
        let url = AppSession.temporaryDirectory().appendingPathComponent("library.json")
        prepare(Library(url: url))
        return url
    }

    // MARK: - Settings

    @Test("Settings… opens from ⌘, and the app menu")
    func settingsWindow() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press(",", "cmd").panels.contains("Settings"))

        let appMenu = try #require(try app.send(ControlRequest(.menu, text: "Silicon Reader")).items)
        #expect(appMenu.starts(with: ["About Silicon Reader", "-", "Settings…"]))
    }

    @Test("documents without remembered state open in the default layout and zoom")
    func defaultView() throws {
        let facing = ViewMode(arrangement: .facing, continuous: false)
        let library = Self.library { $0.settings = Settings(defaultMode: facing, defaultZoom: .fitWidth) }
        let app = try AppSession(documents: [Documents.spec], library: library)
        defer { try? app.quit() }

        let state = try app.waitUntilSettled()

        #expect(state.mode == facing)
        #expect(state.zoom == .fitWidth)
    }

    @Test("with remembering turned off, documents reopen in the default view")
    func rememberStateOff() throws {
        let library = Self.library { $0.settings = Settings(rememberStatePerDocument: false) }

        let first = try AppSession(documents: [Documents.spec], library: library, persist: true)
        try first.waitUntilSettled()
        try first.press("7", "cmd")
        try first.press("end")
        try first.quit()

        let second = try AppSession(documents: [Documents.spec], library: library, persist: true)
        defer { try? second.quit() }
        let state = try second.waitUntilSettled()

        #expect(state.page == 0)
        #expect(state.mode == ViewMode())
    }

    @Test("with session restore turned off, a launch without files shows the home page")
    func restoreSessionOff() throws {
        let library = Self.library { $0.settings = Settings(restoreSession: false) }

        let first = try AppSession(documents: [Documents.spec], library: library, persist: true)
        try first.waitUntilSettled()
        try first.quit()

        let second = try AppSession(library: library, persist: true)
        defer { try? second.quit() }

        #expect(try second.waitUntilSettled().openDocuments.isEmpty)
    }

    // MARK: - Open Recent

    @Test("Open Recent lists existing history files, newest first, and opens them")
    func openRecent() throws {
        let library = Self.library {
            $0.recordOpen(Documents.spec.path, at: Date(timeIntervalSince1970: 1_000))
            $0.recordOpen("/no/such/file.pdf", at: Date(timeIntervalSince1970: 2_000))
            $0.recordOpen(Documents.pdf.path, at: Date(timeIntervalSince1970: 3_000))
        }
        let app = try AppSession(library: library)
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let items = try app.send(ControlRequest(.menu, text: "File/Open Recent")).items
        #expect(items == [Documents.pdf.lastPathComponent, Documents.spec.lastPathComponent, "-", "Clear Menu"])

        let chosen = try app.send(ControlRequest(.menu, name: "djvu2spec.djvu", text: "File/Open Recent"))
        #expect(chosen.handled == true)
        #expect(try app.waitUntilSettled().document == Documents.spec.path)
    }

    @Test("Clear Menu empties Open Recent")
    func clearRecent() throws {
        let library = Self.library { $0.recordOpen(Documents.spec.path) }
        let app = try AppSession(library: library)
        defer { try? app.quit() }
        try app.waitUntilSettled()

        try app.send(ControlRequest(.menu, name: "Clear Menu", text: "File/Open Recent"))

        #expect(try app.send(ControlRequest(.menu, text: "File/Open Recent")).items == ["(Clear Menu)"])
    }

    // MARK: - Drag and drop

    @Test("documents dropped on the home page open as tabs; other files are ignored")
    func dropDocuments() throws {
        let notes = AppSession.temporaryDirectory().appendingPathComponent("notes.txt")
        try Data("not a document".utf8).write(to: notes)
        let app = try AppSession()
        defer { try? app.quit() }
        try app.waitUntilSettled()

        let dropped = try app.send(ControlRequest(.drop, paths: [Documents.spec.path, notes.path, Documents.pdf.path]))
        #expect(dropped.handled == true)
        let state = try app.waitUntilSettled()

        #expect(state.frontTabs == [Documents.spec.path, Documents.pdf.path], "the home tab is replaced")
        #expect(try app.send(ControlRequest(.drop, paths: [notes.path])).handled == false)
    }

    // MARK: - Thumbnails

    @Test("page thumbnails follow the current page and navigate on click")
    func thumbnails() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        #expect(try app.waitUntilSettled().sidebarMode == "bookmarks", "a document with an outline")

        let shown = try app.press("2", "cmd", "option")
        #expect(shown.sidebarVisible)
        #expect(shown.sidebarMode == "thumbnails")
        #expect(shown.thumbnailPage == 0)

        #expect(try app.press("n").thumbnailPage == 1, "the selection follows reading")
        try app.send(ControlRequest(.thumbnail, page: 7))
        let clicked = try app.waitUntilSettled()
        #expect(clicked.page == 7)
        #expect(clicked.thumbnailPage == 7)

        #expect(try app.press("3", "cmd", "option").sidebarMode == "bookmarks")
    }

    @Test("a document without bookmarks offers thumbnails but keeps the sidebar closed")
    func thumbnailsWithoutOutline() throws {
        let app = try AppSession(documents: [Documents.lizard])
        defer { try? app.quit() }

        let state = try app.waitUntilSettled()

        #expect(!state.sidebarVisible)
        #expect(state.sidebarMode == "thumbnails")
    }

    // MARK: - About

    @Test("About is handled by the app with the author's credits")
    func about() throws {
        let app = try AppSession()
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.send(ControlRequest(.resolve, name: "showAbout")).target == "AppDelegate")
        let about = try app.send(ControlRequest(.menu, name: "About Silicon Reader", text: "Silicon Reader"))
        #expect(about.handled == true)
    }
}
