/// Messages of the debug control channel (`SiliconReader -control <socket>`),
/// shared by the app and the e2e tests. One JSON object per line each way.
///
/// Modeled on SumatraPDF's `-dbg-control` channel: tests drive the real app
/// through the same code paths as the user, then assert on reported state
/// instead of pixels.
public struct ControlRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        /// Report `ControlState` for the front document window.
        case state
        /// Press a key: `chars` plus `modifiers` ("cmd", "shift", "option", "ctrl").
        /// Goes through the menu bar for ⌘/⌃ shortcuts, else the canvas key handler.
        case key
        /// Send a menu action by name, e.g. "zoomFitWidth".
        case action
        /// Search for `text` (`forward` defaults to true).
        case find
        /// Select `start..<end` on `page` (0-based scalar indices).
        case select
        /// Open the file at `path` like Open… does.
        case open
        /// Wait until rendering and search are idle (`timeout` seconds, default 10).
        case wait
        /// Report which class would handle action `name` starting from the
        /// window's current focus (`ControlResponse.target`; `handled` = enabled),
        /// without sending it. With `chars`/`modifiers` instead of `name`, report
        /// the action of the menu item bound to that shortcut.
        case resolve
        /// List the menu at `text` ("File/Open Recent") in `ControlResponse.items`,
        /// refreshed the way AppKit does before showing it; with `name`, choose
        /// the item with that title instead.
        case menu
        /// Drop the files at `paths` on the front window, as a Finder drag does.
        case drop
        /// Click the sidebar thumbnail of `page`.
        case thumbnail
        /// Click the toolbar item `name` (its identifier, e.g. "zoomOut"), with
        /// the toolbar's own enabled state as `handled`. With `text`, "zoom"
        /// chooses that entry in the zoom drop-down list and "find" types it into
        /// the search field without searching.
        case toolbar
        case quit
    }

    public var cmd: Command
    public var chars: String?
    public var modifiers: [String]?
    public var name: String?
    public var text: String?
    public var forward: Bool?
    public var page: Int?
    public var start: Int?
    public var end: Int?
    public var path: String?
    public var paths: [String]?
    public var timeout: Double?

    public init(
        _ cmd: Command, chars: String? = nil, modifiers: [String]? = nil, name: String? = nil, text: String? = nil,
        forward: Bool? = nil, page: Int? = nil, start: Int? = nil, end: Int? = nil, path: String? = nil,
        paths: [String]? = nil, timeout: Double? = nil
    ) {
        self.paths = paths
        self.cmd = cmd
        self.chars = chars
        self.modifiers = modifiers
        self.name = name
        self.text = text
        self.forward = forward
        self.page = page
        self.start = start
        self.end = end
        self.path = path
        self.timeout = timeout
    }
}

public struct ControlResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var error: String?
    /// For `key`/`action`: whether something handled it.
    public var handled: Bool?
    /// For `resolve`: class name of the responder that would handle the action.
    public var target: String?
    /// For `menu`: titles of the menu's items ("-" for separators, disabled ones in parentheses).
    public var items: [String]?
    public var state: ControlState?

    public init(
        ok: Bool, error: String? = nil, handled: Bool? = nil, target: String? = nil, items: [String]? = nil,
        state: ControlState? = nil
    ) {
        self.ok = ok
        self.items = items
        self.error = error
        self.handled = handled
        self.target = target
        self.state = state
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message)
    }
}

/// What a test can observe about the front window.
public struct ControlState: Codable, Sendable, Equatable {
    public struct Match: Codable, Sendable, Equatable {
        public var page: Int
        public var start: Int
        public var end: Int

        public init(page: Int, start: Int, end: Int) {
            self.page = page
            self.start = start
            self.end = end
        }
    }

    /// Path of the shown document; nil on the home page.
    public var document: String?
    public var pageCount: Int
    /// 0-based current page.
    public var page: Int
    public var zoom: Zoom?
    public var zoomPercent: Double
    public var mode: ViewMode?
    public var rotation: Int
    public var selectedText: String
    public var searchQuery: String?
    public var match: Match?
    public var sidebarVisible: Bool
    /// "bookmarks" or "thumbnails"; nil on the home page.
    public var sidebarMode: String?
    /// 0-based page selected in the thumbnails, if any.
    public var thumbnailPage: Int?
    /// Titles of other visible windows (Settings, Document Properties, …).
    public var panels: [String]
    public var presenting: Bool
    /// Whether the canvas reaches into the title bar or toolbar (it must not:
    /// with Liquid Glass the pages would cover the title).
    public var canvasUnderToolbar: Bool
    public var invertsColors: Bool
    public var subtitle: String
    /// Document paths of all tabs and windows, front window's tabs first.
    public var openDocuments: [String]
    /// Document paths of the front window's tabs in tab-bar order (empty strings for home tabs).
    public var frontTabs: [String]
    /// Number of separate windows (a window with tabs counts once).
    public var windowCount: Int
    public var settled: Bool

    public init(
        document: String?, pageCount: Int, page: Int, zoom: Zoom?, zoomPercent: Double, mode: ViewMode?,
        rotation: Int, selectedText: String, searchQuery: String?, match: Match?, sidebarVisible: Bool,
        sidebarMode: String? = nil, thumbnailPage: Int? = nil, panels: [String] = [], presenting: Bool,
        canvasUnderToolbar: Bool = false, invertsColors: Bool, subtitle: String, openDocuments: [String],
        frontTabs: [String] = [], windowCount: Int = 1, settled: Bool
    ) {
        self.canvasUnderToolbar = canvasUnderToolbar
        self.sidebarMode = sidebarMode
        self.thumbnailPage = thumbnailPage
        self.panels = panels
        self.document = document
        self.pageCount = pageCount
        self.page = page
        self.zoom = zoom
        self.zoomPercent = zoomPercent
        self.mode = mode
        self.rotation = rotation
        self.selectedText = selectedText
        self.searchQuery = searchQuery
        self.match = match
        self.sidebarVisible = sidebarVisible
        self.presenting = presenting
        self.invertsColors = invertsColors
        self.subtitle = subtitle
        self.openDocuments = openDocuments
        self.frontTabs = frontTabs
        self.windowCount = windowCount
        self.settled = settled
    }
}
