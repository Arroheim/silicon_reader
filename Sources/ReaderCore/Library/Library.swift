import Foundation

/// A document the user has opened.
public struct FileRecord: Codable, Hashable, Sendable {
    public var path: String
    public var openCount: Int
    public var lastOpened: Date
    /// How the document was last shown (SumatraPDF's per-file FileState).
    public var state: ViewState?
    public var sidebarVisible: Bool?

    public init(
        path: String, openCount: Int = 0, lastOpened: Date = .distantPast, state: ViewState? = nil,
        sidebarVisible: Bool? = nil
    ) {
        self.path = path
        self.openCount = openCount
        self.lastOpened = lastOpened
        self.state = state
        self.sidebarVisible = sidebarVisible
    }

    private enum CodingKeys: String, CodingKey { case path, openCount, lastOpened, state, sidebarVisible }

    /// A state written by another version that no longer decodes is dropped,
    /// keeping the rest of the record (and of the history).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        openCount = try c.decode(Int.self, forKey: .openCount)
        lastOpened = try c.decode(Date.self, forKey: .lastOpened)
        state = try? c.decodeIfPresent(ViewState.self, forKey: .state)
        sidebarVisible = try? c.decodeIfPresent(Bool.self, forKey: .sidebarVisible)
    }
}

/// Windows and tabs open when the app quit (SumatraPDF's RestoreSession).
public struct Session: Codable, Hashable, Sendable {
    public struct Window: Codable, Hashable, Sendable {
        /// Document paths in tab order.
        public var tabs: [String]
        public var selectedTab: Int

        public init(tabs: [String], selectedTab: Int = 0) {
            self.tabs = tabs
            self.selectedTab = selectedTab
        }
    }

    public var windows: [Window]

    public init(windows: [Window]) {
        self.windows = windows
    }

    /// Drops documents that no longer exist and windows left without tabs.
    public func filtered(exists: (String) -> Bool) -> Session {
        Session(
            windows: windows.compactMap { window in
                let selected = window.tabs.indices.contains(window.selectedTab) ? window.tabs[window.selectedTab] : nil
                let tabs = window.tabs.filter(exists)
                guard !tabs.isEmpty else { return nil }
                return Window(tabs: tabs, selectedTab: selected.flatMap { tabs.firstIndex(of: $0) } ?? 0)
            })
    }
}

/// A page the user marked in a document (SumatraPDF's Favorites).
public struct Favorite: Codable, Hashable, Sendable {
    public var path: String
    /// 0-based page index.
    public var page: Int
    public var name: String

    public init(path: String, page: Int, name: String) {
        self.path = path
        self.page = page
        self.name = name
    }
}

/// File history and favorites, persisted as JSON.
///
/// Loading never throws: a missing or unreadable file starts an empty library,
/// so a corrupt settings file can't keep the app from launching.
public final class Library: @unchecked Sendable {
    // @unchecked: every access to `state` goes through `lock`.
    private struct State: Codable {
        var files: [FileRecord] = []
        var favorites: [Favorite] = []
        var session: Session?
        /// Optional so libraries written before settings existed still decode.
        var settings: Settings?
    }

    public let url: URL
    private let lock = NSLock()
    private var state: State

    /// Number of entries SumatraPDF keeps in its file history.
    public static let historyLimit = 1000

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
            let decoded = try? Self.decoder.decode(State.self, from: data)
        {
            state = decoded
        } else {
            state = State()
        }
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SiliconReader/library.json")
    }

    // MARK: - History

    public var files: [FileRecord] {
        lock.withLock { state.files }
    }

    /// Records an open of `path` and saves.
    public func recordOpen(_ path: String, at date: Date = Date()) {
        lock.withLock {
            if let i = state.files.firstIndex(where: { $0.path == path }) {
                state.files[i].openCount += 1
                state.files[i].lastOpened = date
            } else {
                state.files.append(FileRecord(path: path, openCount: 1, lastOpened: date))
            }
            if state.files.count > Self.historyLimit {
                state.files.sort { $0.lastOpened > $1.lastOpened }
                state.files.removeLast(state.files.count - Self.historyLimit)
            }
        }
        save()
    }

    public func forget(_ path: String) {
        lock.withLock {
            state.files.removeAll { $0.path == path }
            state.favorites.removeAll { $0.path == path }
        }
        save()
    }

    /// SumatraPDF's "Frequently Read": most opened first, then most recent.
    /// Records that only hold state (never counted as opened) are left out.
    public func frequentlyRead(limit: Int) -> [FileRecord] {
        Array(
            files.filter { $0.openCount > 0 }.sorted {
                ($0.openCount, $0.lastOpened) > ($1.openCount, $1.lastOpened)
            }
            .prefix(limit))
    }

    public func recent(limit: Int) -> [FileRecord] {
        Array(files.filter { $0.openCount > 0 }.sorted { $0.lastOpened > $1.lastOpened }.prefix(limit))
    }

    /// Open Recent's "Clear Menu": files leave the recent and frequently read
    /// lists, but keep their remembered view state and favorites.
    public func clearRecent() {
        lock.withLock {
            for i in state.files.indices { state.files[i].openCount = 0 }
        }
        save()
    }

    // MARK: - Settings

    public var settings: Settings {
        get { lock.withLock { state.settings ?? Settings() } }
        set {
            lock.withLock { state.settings = newValue }
            save()
        }
    }

    // MARK: - Per-file state

    public func record(for path: String) -> FileRecord? {
        lock.withLock { state.files.first { $0.path == path } }
    }

    /// Remembers how `path` is shown. Does not count as an open; a file not yet
    /// in the history gets a record with zero opens.
    public func saveViewState(_ viewState: ViewState, sidebarVisible: Bool, for path: String) {
        lock.withLock {
            if let i = state.files.firstIndex(where: { $0.path == path }) {
                state.files[i].state = viewState
                state.files[i].sidebarVisible = sidebarVisible
            } else {
                state.files.append(FileRecord(path: path, state: viewState, sidebarVisible: sidebarVisible))
            }
        }
        save()
    }

    // MARK: - Session

    public var session: Session? {
        lock.withLock { state.session }
    }

    /// Stores the windows to reopen next launch; nil or no windows clears it.
    public func saveSession(_ session: Session?) {
        lock.withLock { state.session = session?.windows.isEmpty == false ? session : nil }
        save()
    }

    // MARK: - Favorites

    public var favorites: [Favorite] {
        lock.withLock { state.favorites }
    }

    public func favorites(for path: String) -> [Favorite] {
        favorites.filter { $0.path == path }.sorted { $0.page < $1.page }
    }

    /// Adds a favorite, replacing the name of an existing one on the same page.
    public func addFavorite(_ favorite: Favorite) {
        lock.withLock {
            if let i = state.favorites.firstIndex(where: { $0.path == favorite.path && $0.page == favorite.page }) {
                state.favorites[i].name = favorite.name
            } else {
                state.favorites.append(favorite)
            }
        }
        save()
    }

    public func removeFavorite(path: String, page: Int) {
        lock.withLock { state.favorites.removeAll { $0.path == path && $0.page == page } }
        save()
    }

    // MARK: - Persistence

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private func save() {
        let snapshot = lock.withLock { state }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            // Losing history is not worth interrupting reading; nothing else to do here.
        }
    }
}
