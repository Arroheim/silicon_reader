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
    public var timeout: Double?

    public init(
        _ cmd: Command, chars: String? = nil, modifiers: [String]? = nil, name: String? = nil, text: String? = nil,
        forward: Bool? = nil, page: Int? = nil, start: Int? = nil, end: Int? = nil, path: String? = nil,
        timeout: Double? = nil
    ) {
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
    public var state: ControlState?

    public init(ok: Bool, error: String? = nil, handled: Bool? = nil, state: ControlState? = nil) {
        self.ok = ok
        self.error = error
        self.handled = handled
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
    public var presenting: Bool
    public var invertsColors: Bool
    public var subtitle: String
    /// Document paths of all tabs and windows, front window's tabs first.
    public var openDocuments: [String]
    public var settled: Bool

    public init(
        document: String?, pageCount: Int, page: Int, zoom: Zoom?, zoomPercent: Double, mode: ViewMode?,
        rotation: Int, selectedText: String, searchQuery: String?, match: Match?, sidebarVisible: Bool,
        presenting: Bool, invertsColors: Bool, subtitle: String, openDocuments: [String], settled: Bool
    ) {
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
        self.settled = settled
    }
}
