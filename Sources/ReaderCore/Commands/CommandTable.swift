/// One user command: what it is called, which action handles it and its keys.
///
/// `id` uses SumatraPDF's command names so the debug hook, keyboard help and a
/// future command palette speak the same language as Sumatra's docs.
public struct Command: Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case file = "File"
        case edit = "Edit"
        case view = "View"
        case go = "Go"
        case favorites = "Favorites"
        case window = "Window"
        case help = "Help"
    }

    public var id: String
    public var title: String
    public var group: Group
    /// Objective-C action name (without the trailing colon).
    public var action: String
    /// First is the one shown in menus; the rest are alternates.
    public var shortcuts: [Shortcut]
    /// Listed in keyboard help but not given a menu item (scrolling etc.).
    public var hiddenFromMenu: Bool

    public init(
        _ id: String, _ title: String, _ group: Group, action: String, _ shortcuts: [Shortcut] = [],
        hiddenFromMenu: Bool = false
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.action = action
        self.shortcuts = shortcuts
        self.hiddenFromMenu = hiddenFromMenu
    }
}

/// SumatraPDF's keyboard map (src/shared/Accelerators.cpp) adapted to macOS:
/// Ctrl becomes ⌘, Sumatra's own macOS overrides (⌘0 actual size, ⌘9 fit page,
/// ⌘[ / ⌘] back/forward, ⌃⌘S sidebar …) are used where it defines them, and
/// combinations macOS reserves are replaced (noted inline).
public enum CommandTable {
    private static func key(_ c: Character, _ m: KeyModifiers = []) -> Shortcut { Shortcut(.character(c), m) }
    private static func key(_ k: Key, _ m: KeyModifiers = []) -> Shortcut { Shortcut(k, m) }
    private static let cmd: KeyModifiers = .command
    private static let shiftCmd: KeyModifiers = [.shift, .command]
    private static let optCmd: KeyModifiers = [.option, .command]
    private static let ctrlCmd: KeyModifiers = [.control, .command]

    public static let all: [Command] = [
        // File
        Command("CmdNewWindow", "New Window", .file, action: "newWindow", [key("n", cmd)]),
        Command(
            "CmdDuplicateInNewWindow", "Duplicate in New Window", .file, action: "duplicateInNewWindow",
            [key("n", shiftCmd)]),
        Command("CmdOpenFile", "Open…", .file, action: "openDocument", [key("o", cmd)]),
        Command(
            "CmdReopenLastClosedFile", "Reopen Last Closed", .file, action: "reopenLastClosed", [key("t", shiftCmd)]),
        Command(
            "CmdOpenNextFileInFolder", "Open Next File in Folder", .file, action: "openNextFileInFolder",
            [key(.right, shiftCmd)]),
        Command(
            "CmdOpenPrevFileInFolder", "Open Previous File in Folder", .file, action: "openPreviousFileInFolder",
            [key(.left, shiftCmd)]),
        Command("CmdSaveAs", "Save a Copy…", .file, action: "saveDocumentCopy", [key("s", cmd)]),
        Command("CmdReloadDocument", "Reload", .file, action: "reloadDocument", [key("r")]),
        Command("CmdClose", "Close", .file, action: "performClose", [key("w", cmd)]),
        Command("CmdCloseCurrentDocument", "Close Document", .file, action: "closeDocument", [key("q")]),
        Command("CmdPrint", "Print…", .file, action: "printDocument", [key("p", cmd)]),

        // Edit
        Command("CmdCopySelection", "Copy", .edit, action: "copy", [key("c", cmd)]),
        Command("CmdSelectAll", "Select All", .edit, action: "selectAll", [key("a", cmd)]),
        Command("CmdFindFirst", "Find…", .edit, action: "showFind", [key("f", cmd)]),
        Command("CmdFindNext", "Find Next", .edit, action: "findNext", [key("g", cmd), key(.function(3))]),
        Command(
            "CmdFindPrev", "Find Previous", .edit, action: "findPrevious",
            [key("g", shiftCmd), key(.function(3), .shift)]),
        Command("CmdFindMatchCase", "Match Case", .edit, action: "toggleMatchCase"),

        // View
        Command(
            "CmdToggleBookmarks", "Show Sidebar", .view, action: "toggleSidebar",
            [key("s", ctrlCmd), key(.function(12))]),
        Command("CmdToggleToolbar", "Show Toolbar", .view, action: "toggleToolbarShown", [key("t", optCmd)]),
        Command("CmdSinglePageView", "Single Page", .view, action: "viewSinglePage", [key("6", cmd)]),
        Command("CmdFacingView", "Facing", .view, action: "viewFacing", [key("7", cmd)]),
        Command("CmdBookView", "Book View", .view, action: "viewBook", [key("8", cmd)]),
        Command("CmdToggleContinuousView", "Continuous", .view, action: "toggleContinuous", [key("c")]),
        Command("CmdZoomFitPage", "Fit Page", .view, action: "zoomFitPage", [key("9", cmd)]),
        Command("CmdZoomActualSize", "Actual Size", .view, action: "zoomActualSize", [key("0", cmd)]),
        Command("CmdZoomFitWidth", "Fit Width", .view, action: "zoomFitWidth", [key("2", cmd)]),
        Command("CmdZoomFitContent", "Fit Content", .view, action: "zoomFitContent", [key("3", cmd)]),
        Command("CmdZoomIn", "Zoom In", .view, action: "zoomIn", [key("+", cmd), key("=", cmd)]),
        Command("CmdZoomOut", "Zoom Out", .view, action: "zoomOut", [key("-", cmd)]),
        Command("CmdZoomCustom", "Zoom To…", .view, action: "customZoom", [key("y", cmd)]),
        Command("CmdZoomToSelection", "Zoom to Selection", .view, action: "zoomToSelection", [key("4", cmd)]),
        Command("CmdToggleZoom", "Toggle Zoom", .view, action: "toggleZoom", [key("z")]),
        // Sumatra's Ctrl+Shift+Plus/Minus rely on the numpad: on a Mac keyboard
        // ⇧⌘= is the same chord as ⌘+ (zoom in). Preview's ⌘L / ⌘R instead.
        Command("CmdRotateLeft", "Rotate Left", .view, action: "rotateLeft", [key("l", cmd), key("[")]),
        Command("CmdRotateRight", "Rotate Right", .view, action: "rotateRight", [key("r", cmd), key("]")]),
        Command("CmdInvertColors", "Invert Colors", .view, action: "invertColors", [key("i", .shift)]),
        Command("CmdTogglePageInfo", "Show Page Info", .view, action: "togglePageInfo", [key("i")]),
        Command("CmdToggleCursorPosition", "Show Cursor Position", .view, action: "toggleCursorPosition", [key("m")]),
        // ⌃⌘F is the macOS full screen shortcut; F11 is taken by "Show Desktop".
        Command(
            "CmdToggleFullscreen", "Full Screen", .view, action: "toggleFullScreen", [key("f", ctrlCmd), key("f")]),
        // Ctrl+L / F5 / Shift+F11 in Sumatra; ⇧⌘F is Sumatra's own macOS mapping
        // (⌘L rotates left here, as in Preview).
        Command(
            "CmdTogglePresentationMode", "Presentation", .view, action: "togglePresentation",
            [key("f", shiftCmd), key(.function(5))]),
        Command(
            "CmdPresentationBlackBackground", "Black Screen", .view, action: "presentationBlackScreen", [key(".")],
            hiddenFromMenu: true),
        Command(
            "CmdPresentationWhiteBackground", "White Screen", .view, action: "presentationWhiteScreen", [key("w")],
            hiddenFromMenu: true),
        Command(
            "CmdToggleAutomaticallyScroll", "Scroll Automatically", .view, action: "toggleAutoScroll",
            [key("h", shiftCmd)]),

        // Go
        Command("CmdGoToNextPage", "Next Page", .go, action: "goToNextPage", [key("n")]),
        Command("CmdGoToPrevPage", "Previous Page", .go, action: "goToPreviousPage", [key("p")]),
        Command("CmdGoToFirstPage", "First Page", .go, action: "goToFirstPage", [key(.up, cmd), key(.home)]),
        Command("CmdGoToLastPage", "Last Page", .go, action: "goToLastPage", [key(.down, cmd), key(.end)]),
        // ⌘G is Find Next on macOS (Sumatra's mac table agrees), so Go To Page is ⌥⌘G.
        Command("CmdGoToPage", "Go to Page…", .go, action: "goToPageNumber", [key("g", optCmd), key("g")]),
        Command("CmdNavigateBack", "Back", .go, action: "navigateBack", [key("[", cmd), key(.backspace)]),
        Command(
            "CmdNavigateForward", "Forward", .go, action: "navigateForward",
            [key("]", cmd), key(.backspace, .shift)]),
        Command(
            "CmdScrollDown", "Scroll Down", .go, action: "scrollLineDown", [key("j"), key(.down)], hiddenFromMenu: true),
        Command("CmdScrollUp", "Scroll Up", .go, action: "scrollLineUp", [key("k"), key(.up)], hiddenFromMenu: true),
        Command(
            "CmdScrollLeft", "Scroll Left", .go, action: "scrollLineLeft", [key("h"), key(.left)], hiddenFromMenu: true),
        Command(
            "CmdScrollRight", "Scroll Right", .go, action: "scrollLineRight", [key("l"), key(.right)],
            hiddenFromMenu: true),
        Command(
            "CmdScrollDownHalfPage", "Scroll Down Half a Page", .go, action: "scrollHalfPageDown",
            [key(.down, .shift)], hiddenFromMenu: true),
        Command(
            "CmdScrollUpHalfPage", "Scroll Up Half a Page", .go, action: "scrollHalfPageUp", [key(.up, .shift)],
            hiddenFromMenu: true),
        Command(
            "CmdScrollLeftPage", "Scroll Left a Screen", .go, action: "scrollScreenLeft", [key(.left, .shift)],
            hiddenFromMenu: true),
        Command(
            "CmdScrollRightPage", "Scroll Right a Screen", .go, action: "scrollScreenRight", [key(.right, .shift)],
            hiddenFromMenu: true),
        Command(
            "CmdScrollDownPage", "Scroll Down a Screen", .go, action: "scrollScreenDown",
            [key(.pageDown), key(.space), key(.enter), key(.down, .option)], hiddenFromMenu: true),
        Command(
            "CmdScrollUpPage", "Scroll Up a Screen", .go, action: "scrollScreenUp",
            [key(.pageUp), key(.space, .shift), key(.enter, .shift), key(.up, .option)], hiddenFromMenu: true),

        // Favorites
        Command("CmdFavoriteAdd", "Add to Favorites…", .favorites, action: "addFavorite", [key("d", cmd)]),

        // Window
        // ⇧⌘[ / ⇧⌘] produce "{" / "}", which is how they are matched.
        Command("CmdPrevTab", "Show Previous Tab", .window, action: "selectPreviousTab", [key("{", cmd)]),
        Command("CmdNextTab", "Show Next Tab", .window, action: "selectNextTab", [key("}", cmd)]),
        Command("CmdMoveFrameFocus", "Move Focus", .window, action: "moveFrameFocus", [key(.function(6))]),

        // Help
        Command("CmdToggleKeyboardHelp", "Keyboard Shortcuts", .help, action: "showKeyboardHelp", [key("?")]),
    ]

    public static func command(id: String) -> Command? {
        all.first { $0.id == id }
    }

    private static let byShortcut: [Shortcut: Command] = {
        var map: [Shortcut: Command] = [:]
        for command in all {
            for shortcut in command.shortcuts { map[shortcut] = command }
        }
        return map
    }()

    public static func command(for shortcut: Shortcut) -> Command? {
        byShortcut[shortcut]
    }

    public static func commands(in group: Command.Group) -> [Command] {
        all.filter { $0.group == group }
    }
}
