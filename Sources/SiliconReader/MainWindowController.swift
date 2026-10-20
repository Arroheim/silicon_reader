import AppKit
import ReaderCore

/// Selectors for toolbar/menu commands whose handlers arrive in later
/// milestones. Until something in the responder chain implements them, AppKit
/// shows their items disabled.
@objc protocol PendingCommands {
    func printDocument(_ sender: Any?)
    func showFind(_ sender: Any?)
}

/// One window (tab) showing either the home page or a document, with
/// SumatraPDF's toolbar.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let library: Library
    private let thumbnails: ThumbnailStore
    private let onOpen: (URL, MainWindowController) -> Void
    private(set) var currentDocument: DocumentViewController?
    private lazy var toolbarController = ToolbarController(windowController: self)

    var onClose: (() -> Void)?

    /// `restoresFrame` is off for debug snapshots so their size doesn't depend on the user's last window.
    init(
        library: Library, thumbnails: ThumbnailStore, restoresFrame: Bool = true,
        onOpen: @escaping (URL, MainWindowController) -> Void
    ) {
        self.library = library
        self.thumbnails = thumbnails
        self.onOpen = onOpen
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "SiliconReader"
        // Title on its own row and the toolbar below, like SumatraPDF's
        // caption + toolbar; the full width fits all of its buttons.
        window.toolbarStyle = .expanded
        window.contentMinSize = Self.minimumSize
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = toolbarController
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        showHome()

        // Restore the saved frame, but not a degenerate one (an earlier build
        // let the content shrink the window and saved that).
        if restoresFrame {
            window.setFrameAutosaveName("MainWindow")
        }
        if window.frame.width < Self.minimumSize.width || window.frame.height < Self.minimumSize.height {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
    }

    private static let minimumSize = NSSize(width: 640, height: 480)
    private static let defaultSize = NSSize(width: 1000, height: 1000)

    /// Swaps the content without letting the new view controller resize the window.
    private func setContent(_ controller: NSViewController) {
        let frame = window?.frame
        contentViewController = controller
        if let frame, let window {
            window.setFrame(frame, display: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isShowingHome: Bool { currentDocument == nil }
    var canvas: DocumentView? { currentDocument?.canvas }

    /// True once whatever is shown has finished rendering (debug snapshot hook).
    var isSettled: Bool { canvas?.isSettled ?? true }

    func showHome() {
        currentDocument = nil
        let home = HomeViewController(library: library, thumbnails: thumbnails) { [weak self] url in
            guard let self else { return }
            onOpen(url, self)
        }
        setContent(home)
        window?.title = "Silicon Reader"
        window?.subtitle = ""
        window?.representedURL = nil
        toolbarController.update()
    }

    func show(_ engine: any DocumentEngine) {
        let controller = DocumentViewController(engine: engine, library: library)
        controller.onStateChange = { [weak self] in self?.toolbarController.update() }
        currentDocument = controller
        setContent(controller)
        window?.title = engine.url.lastPathComponent
        window?.representedURL = engine.url
        toolbarController.update()
    }

    /// Sends a menu action straight to the canvas (debug hook), regardless of focus.
    func perform(_ action: Selector) -> Bool {
        guard let canvas else { return false }
        return NSApp.sendAction(action, to: canvas, from: nil)
    }

    /// PNG of the whole window (title bar and toolbar included) as currently drawn.
    func snapshotPNG() -> Data? {
        guard let view = window?.contentView?.superview ?? window?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - NSWindowDelegate

    /// Like SumatraPDF, closing the last document shows the home page instead of closing the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let otherWindows = NSApp.windows.filter { $0 !== sender && $0.windowController is MainWindowController }
        if currentDocument != nil && otherWindows.allSatisfy({ !$0.isVisible }) {
            showHome()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
