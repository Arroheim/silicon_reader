import AppKit
import ReaderCore

/// Selectors for toolbar/menu commands whose handlers arrive in later
/// milestones. Until something in the responder chain implements them, AppKit
/// shows their items disabled.
@objc protocol PendingCommands {
    func printDocument(_ sender: Any?)
    func showFind(_ sender: Any?)
}

/// What a window needs from the app: opening files and tracking closed ones.
@MainActor
protocol MainWindowHost: AnyObject {
    /// Opens `url` the way a home page click or Open… does.
    func open(_ url: URL, from window: MainWindowController)
    /// Opens the engine for `url`, asking for a password if needed.
    func openEngine(_ url: URL) -> (any DocumentEngine)?
    /// Opens `url` in a separate window showing `state`.
    func openInNewWindow(_ url: URL, state: ViewState)
    /// A document stopped being shown (closed, replaced); for Reopen Last Closed.
    func documentDidClose(_ url: URL)
    /// A document was shown in a window; records history and thumbnails.
    func documentDidOpen(_ engine: any DocumentEngine)
}

/// One window (tab) showing either the home page or a document, with
/// SumatraPDF's toolbar.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let library: Library
    private let thumbnails: ThumbnailStore
    private weak var host: MainWindowHost?
    private(set) var currentDocument: DocumentViewController?
    private lazy var toolbarController = ToolbarController(windowController: self)
    private var presentation: PresentationState?

    var onClose: (() -> Void)?

    /// What presentation mode changed, so leaving it restores everything.
    private struct PresentationState {
        let view: ViewState
        let sidebarCollapsed: Bool
        let toolbarVisible: Bool
        let wasFullScreen: Bool
    }

    /// `restoresFrame` is off for debug snapshots so their size doesn't depend on the user's last window.
    init(library: Library, thumbnails: ThumbnailStore, host: MainWindowHost, restoresFrame: Bool = true) {
        self.library = library
        self.thumbnails = thumbnails
        self.host = host
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
    var documentURL: URL? { currentDocument?.engine.url }

    /// True once whatever is shown has finished rendering (debug snapshot hook).
    var isSettled: Bool { canvas?.isSettled ?? true }

    func showHome() {
        if presentation != nil { togglePresentation(nil) }
        if let url = documentURL { host?.documentDidClose(url) }
        currentDocument = nil
        let home = HomeViewController(library: library, thumbnails: thumbnails) { [weak self] url in
            guard let self else { return }
            host?.open(url, from: self)
        }
        setContent(home)
        window?.title = "Silicon Reader"
        window?.subtitle = ""
        window?.representedURL = nil
        toolbarController.update()
    }

    func show(_ engine: any DocumentEngine, state: ViewState? = nil) {
        if let url = documentURL, url != engine.url { host?.documentDidClose(url) }
        let controller = DocumentViewController(engine: engine, library: library, state: state)
        controller.onStateChange = { [weak self] in self?.toolbarController.update() }
        currentDocument = controller
        setContent(controller)
        window?.title = engine.url.lastPathComponent
        window?.representedURL = engine.url
        toolbarController.update()
        host?.documentDidOpen(engine)
    }

    /// Sends a menu action to the first of canvas, document, window controller
    /// and app delegate that handles it (debug hook), regardless of focus.
    func perform(_ action: Selector) -> Bool {
        let targets: [AnyObject?] = [canvas, currentDocument, self, NSApp.delegate]
        guard let target = targets.compactMap({ $0 }).first(where: { $0.responds(to: action) }) else { return false }
        return NSApp.sendAction(action, to: target, from: nil)
    }

    /// PNG of the whole window (title bar and toolbar included) as currently drawn.
    func snapshotPNG() -> Data? {
        guard let view = window?.contentView?.superview ?? window?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Document commands

    /// Sumatra's next/previous file in folder replaces the document in this tab.
    @objc func openNextFileInFolder(_ sender: Any?) { openSibling(forward: true) }
    @objc func openPreviousFileInFolder(_ sender: Any?) { openSibling(forward: false) }

    private func openSibling(forward: Bool) {
        guard let url = documentURL else { return }
        guard let next = FolderNavigation.sibling(of: url, forward: forward) else {
            NSSound.beep()
            flash(forward ? "No next file in this folder" : "No previous file in this folder")
            return
        }
        if let engine = host?.openEngine(next) { show(engine) }
    }

    /// Re-reads the file from disk, keeping page, zoom and layout.
    @objc func reloadDocument(_ sender: Any?) {
        guard let url = documentURL, let state = canvas?.viewState,
            let engine = host?.openEngine(url)
        else { return }
        show(engine, state: state)
    }

    @objc func closeDocument(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc func duplicateInNewWindow(_ sender: Any?) {
        guard let url = documentURL, let state = canvas?.viewState else { return }
        host?.openInNewWindow(url, state: state)
    }

    /// SumatraPDF's Save As: writes a copy of the file somewhere else.
    @objc func saveDocumentCopy(_ sender: Any?) {
        guard let url = documentURL, let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.directoryURL = url.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url, target != url else { return }
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: url, to: target)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// g / ⌥⌘G: the toolbar's page box, or a prompt when the toolbar is hidden.
    @objc func goToPageNumber(_ sender: Any?) {
        guard let canvas else { return }
        if window?.toolbar?.isVisible == true, toolbarController.focusPageField() { return }
        guard let text = prompt("Go to Page", message: "Page number or label (1–\(canvas.pageCount)):") else { return }
        if let page = UserInput.page(text, pageCount: canvas.pageCount, label: canvas.engine.pageLabel(at:)) {
            canvas.jump(toPage: page)
        } else {
            NSSound.beep()
        }
    }

    /// ⌘Y: the toolbar's zoom box, or a prompt when the toolbar is hidden.
    @objc func customZoom(_ sender: Any?) {
        guard let canvas else { return }
        if window?.toolbar?.isVisible == true, toolbarController.focusZoomBox() { return }
        guard let text = prompt("Zoom To", message: "Zoom in percent (8.33–6400) or Fit Page, Fit Width…") else {
            return
        }
        if let zoom = UserInput.zoom(text) { canvas.setZoom(zoom) } else { NSSound.beep() }
    }

    private func prompt(_ title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// A short message in the window's subtitle (Sumatra shows a notification).
    private func flash(_ message: String) {
        window?.subtitle = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.window?.subtitle == message { self?.window?.subtitle = "" }
        }
    }

    // MARK: - Presentation

    /// SumatraPDF's presentation mode: full screen, no chrome, one fitted page
    /// on black. Leaving restores the previous layout.
    @objc func togglePresentation(_ sender: Any?) {
        guard let window, let document = currentDocument else { return }
        if let saved = presentation {
            presentation = nil
            document.canvas.setPresenting(false)
            var restored = saved.view
            restored.position = DocumentPosition(page: document.canvas.currentPage)
            document.canvas.apply(restored)
            document.isSidebarCollapsed = saved.sidebarCollapsed
            window.toolbar?.isVisible = saved.toolbarVisible
            if !saved.wasFullScreen && window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        } else {
            let canvas = document.canvas
            presentation = PresentationState(
                view: canvas.viewState, sidebarCollapsed: document.isSidebarCollapsed,
                toolbarVisible: window.toolbar?.isVisible ?? true,
                wasFullScreen: window.styleMask.contains(.fullScreen))
            document.isSidebarCollapsed = true
            window.toolbar?.isVisible = false
            canvas.setPresenting(true)
            let single = ViewMode(arrangement: .single, continuous: false)
            let page = DocumentPosition(page: canvas.currentPage)
            canvas.apply(ViewState(mode: single, zoom: .fitPage, rotation: canvas.rotation, position: page))
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
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
        if let url = documentURL { host?.documentDidClose(url) }
        onClose?()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Leaving full screen by other means (green button, ⌃⌘F) ends presentation too.
        if presentation != nil { togglePresentation(nil) }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(togglePresentation(_:)) {
            item.state = presentation != nil ? .on : .off
        }
        // Everything here acts on the shown document.
        return currentDocument != nil
    }
}
