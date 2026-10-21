import Foundation
import Testing

@testable import ReaderCore

@Suite("Settings")
struct SettingsTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("library.json")

    @Test("defaults match SumatraPDF's")
    func defaults() {
        let settings = Settings()

        #expect(settings.initialViewState == ViewState(position: DocumentPosition(page: 0)))
        #expect(settings.rememberStatePerDocument)
        #expect(settings.restoreSession)
        #expect(settings.reloadModifiedDocuments)
    }

    @Test("persist in the library file")
    func persistence() {
        let library = Library(url: url)
        library.settings = Settings(
            defaultMode: ViewMode(arrangement: .book, continuous: false), defaultZoom: .percent(125),
            restoreSession: false)

        let reloaded = Library(url: url).settings

        #expect(reloaded.defaultMode == ViewMode(arrangement: .book, continuous: false))
        #expect(reloaded.defaultZoom == .percent(125))
        #expect(!reloaded.restoreSession)
        #expect(reloaded.rememberStatePerDocument)
    }

    @Test("a library written before settings existed keeps its history and gets defaults")
    func olderLibrary() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
            {"favorites": [], "files": [{"path": "/a.pdf", "openCount": 2, "lastOpened": "2026-01-01T00:00:00Z"}]}
            """
        try Data(json.utf8).write(to: url)

        let library = Library(url: url)

        #expect(library.files.map(\.path) == ["/a.pdf"])
        #expect(library.settings == Settings())
    }

    @Test("unknown or broken keys fall back one by one")
    func partialDecode() throws {
        let json = #"{"defaultZoom": "fit width", "restoreSession": "maybe", "defaultMode": 7}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))

        #expect(settings.defaultZoom == .fitWidth)
        #expect(settings.restoreSession, "a broken value keeps the default")
        #expect(settings.defaultMode == ViewMode())
    }

    @Test("clearing recent files keeps their view state and favorites")
    func clearRecent() {
        let library = Library(url: url)
        library.recordOpen("/a.pdf")
        let state = ViewState(zoom: .fitWidth, position: DocumentPosition(page: 4))
        library.saveViewState(state, sidebarVisible: true, for: "/a.pdf")
        library.addFavorite(Favorite(path: "/a.pdf", page: 2, name: "Two"))

        library.clearRecent()

        #expect(library.recent(limit: 10).isEmpty)
        #expect(library.frequentlyRead(limit: 10).isEmpty)
        #expect(library.record(for: "/a.pdf")?.state == state)
        #expect(library.favorites(for: "/a.pdf").count == 1)
    }
}

@Suite("Document opener")
struct DocumentOpenerCanOpenTests {
    @Test("accepts PDF and DjVu files, by header or extension")
    func accepts() throws {
        #expect(DocumentOpener.canOpen(try Fixtures.url("djvu2spec.djvu")))
        let renamed = try Fixtures.temporaryFile("book.bin", contents: Data("%PDF-1.7\n".utf8))
        #expect(DocumentOpener.canOpen(renamed), "sniffed from the header")
    }

    @Test("rejects other files, folders and missing paths")
    func rejects() throws {
        let text = try Fixtures.temporaryFile("notes.txt", contents: Data("hello".utf8))
        #expect(!DocumentOpener.canOpen(text))
        #expect(!DocumentOpener.canOpen(text.deletingLastPathComponent()))
        #expect(!DocumentOpener.canOpen(URL(fileURLWithPath: "/no/such/book.pdf")))
        #expect(!DocumentOpener.canOpen(URL(string: "https://example.com/a.pdf")!))
    }
}
