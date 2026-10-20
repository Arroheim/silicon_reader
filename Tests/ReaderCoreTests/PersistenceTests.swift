import Foundation
import Testing

@testable import ReaderCore

@Suite("Saved state")
struct PersistenceTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("library.json")

    private static let state = ViewState(
        mode: ViewMode(arrangement: .book, continuous: false), zoom: .percent(150), rotation: 90,
        position: DocumentPosition(page: 7, point: CGPoint(x: 12.5, y: 300)))

    @Test(
        "stores zoom like SumatraPDF's settings",
        arguments: [
            (Zoom.fitPage, "\"fit page\""), (.fitWidth, "\"fit width\""), (.fitContent, "\"fit content\""),
            (.percent(125), "125"), (.percent(66.67), "66.67"),
        ])
    func zoomEncoding(zoom: Zoom, json: String) throws {
        let data = try JSONEncoder().encode(zoom)
        #expect(String(decoding: data, as: UTF8.self) == json)
        #expect(try JSONDecoder().decode(Zoom.self, from: data) == zoom)
    }

    @Test("rejects unknown zoom names and clamps numbers")
    func zoomDecoding() throws {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Zoom.self, from: Data("\"huge\"".utf8)) }
        #expect(try JSONDecoder().decode(Zoom.self, from: Data("100000".utf8)) == .percent(6400))
    }

    @Test("round-trips a view state")
    func viewStateRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.state)
        #expect(try JSONDecoder().decode(ViewState.self, from: data) == Self.state)
    }

    @Test("remembers state per file without counting it as an open")
    func perFileState() {
        let library = Library(url: url)
        library.saveViewState(Self.state, sidebarVisible: false, for: "/a.pdf")

        let reloaded = Library(url: url)
        let record = reloaded.record(for: "/a.pdf")

        #expect(record?.state == Self.state)
        #expect(record?.sidebarVisible == false)
        #expect(record?.openCount == 0)
        #expect(reloaded.frequentlyRead(limit: 10).isEmpty, "state alone is not reading history")
        #expect(reloaded.recent(limit: 10).isEmpty)
    }

    @Test("keeps open counts when saving state for a known file")
    func stateKeepsHistory() {
        let library = Library(url: url)
        library.recordOpen("/a.pdf")
        library.saveViewState(Self.state, sidebarVisible: true, for: "/a.pdf")

        #expect(library.record(for: "/a.pdf")?.openCount == 1)
        #expect(library.frequentlyRead(limit: 10).map(\.path) == ["/a.pdf"])
    }

    @Test("drops an unreadable state but keeps the record")
    func corruptState() throws {
        let json = """
            {"files":[{"path":"/a.pdf","openCount":3,"lastOpened":"2026-01-01T00:00:00Z",
            "state":{"zoom":"huge"}}],"favorites":[]}
            """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let record = Library(url: url).record(for: "/a.pdf")

        #expect(record?.openCount == 3)
        #expect(record?.state == nil)
    }

    @Test("reads libraries written before per-file state existed")
    func oldFormat() throws {
        let json = """
            {"files":[{"path":"/a.pdf","openCount":2,"lastOpened":"2026-01-01T00:00:00Z"}],"favorites":[]}
            """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let library = Library(url: url)

        #expect(library.record(for: "/a.pdf")?.openCount == 2)
        #expect(library.session == nil)
    }

    @Test("saves and clears the session")
    func session() {
        let library = Library(url: url)
        let session = Session(windows: [Session.Window(tabs: ["/a.pdf", "/b.djvu"], selectedTab: 1)])

        library.saveSession(session)
        #expect(Library(url: url).session == session)

        library.saveSession(Session(windows: []))
        #expect(Library(url: url).session == nil)
    }

    @Test("filters missing documents out of a session, keeping the selected tab")
    func sessionFilter() {
        let session = Session(windows: [
            Session.Window(tabs: ["/gone.pdf", "/a.pdf", "/b.pdf"], selectedTab: 2),
            Session.Window(tabs: ["/gone.pdf"]),
            Session.Window(tabs: ["/c.pdf"], selectedTab: 5),
        ])

        let filtered = session.filtered { $0 != "/gone.pdf" }

        #expect(
            filtered.windows == [
                Session.Window(tabs: ["/a.pdf", "/b.pdf"], selectedTab: 1),
                Session.Window(tabs: ["/c.pdf"], selectedTab: 0),
            ])
    }
}

@Suite("File watcher")
struct FileWatcherTests {
    /// Counts callbacks from the watcher's queue.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    private func makeFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.pdf")
        try Data("v1".utf8).write(to: url)
        return url
    }

    /// Polls until `condition` holds or the deadline passes.
    private func eventually(within seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func watch(_ url: URL, _ counter: Counter) -> FileWatcher {
        FileWatcher(url: url, debounce: .milliseconds(50), queue: DispatchQueue(label: "test")) {
            counter.increment()
        }
    }

    @Test("reports an in-place write once, debounced")
    func inPlaceWrite() async throws {
        let url = try makeFile()
        let counter = Counter()
        let watcher = watch(url, counter)
        try await Task.sleep(for: .milliseconds(100))

        let handle = try FileHandle(forWritingTo: url)
        for chunk in ["a", "b", "c"] { try handle.write(contentsOf: Data(chunk.utf8)) }
        try handle.close()

        #expect(await eventually { counter.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(counter.count == 1, "a burst of writes is one change")
        watcher.stop()
    }

    @Test("follows an atomic save that replaces the file")
    func atomicReplace() async throws {
        let url = try makeFile()
        let counter = Counter()
        let watcher = watch(url, counter)
        try await Task.sleep(for: .milliseconds(100))

        try Data("v2".utf8).write(to: url, options: .atomic)
        #expect(await eventually { counter.count >= 1 })

        // Still attached to the new file afterwards.
        let before = counter.count
        try await Task.sleep(for: .milliseconds(300))
        try Data("v3".utf8).write(to: url, options: .atomic)
        #expect(await eventually { counter.count > before })
        watcher.stop()
    }

    @Test("stays quiet after stop")
    func stop() async throws {
        let url = try makeFile()
        let counter = Counter()
        let watcher = watch(url, counter)
        try await Task.sleep(for: .milliseconds(100))

        watcher.stop()
        try await Task.sleep(for: .milliseconds(50))
        try Data("v2".utf8).write(to: url)

        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.count == 0)
    }
}
