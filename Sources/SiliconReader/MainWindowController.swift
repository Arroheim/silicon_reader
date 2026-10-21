import AppKit
import ReaderCore

/// What a window needs from the app: opening files and tracking closed ones.
@MainActor
protocol MainWindowHost: AnyObject {
    /// Opens `url` the way a home page click or Open… does; returns the window showing it.
    @discardableResult
    func open(_ url: URL, from window: MainWindowController) -> MainWindowController?
    /// Opens the engine for `url`, asking for a password if needed.
    func openEngine(_ url: URL) -> (any DocumentEngine)?
    /// Opens `url` in a separate window showing `state`.
    func openInNewWindow(_ url: URL, state: ViewState)
    /// A document stopped being shown (closed, replaced); for Reopen Last Closed.
    func documentDidClose(_ url: URL)
    /// A document was shown in a window. `countsAsOpen` is false for reloads
    /// and session restore, which shouldn't raise it in "Frequently Read".
    func documentDidOpen(_ engine: any DocumentEngine, countsAsOpen: Bool)
}

/// One window (tab) showing either the home page or a document, with
/// SumatraPDF's toolbar.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let library: Library
    private let thumbnails: ThumbnailStore
    private weak var host: MainWindowHost?
    private let persistsState: Bool
    private(set) var currentDocument: DocumentViewController?
    private lazy var toolbarController = ToolbarController(windowController: self)
    private var presentation: PresentationState?
    /// Reloads the document when its file changes (SumatraPDF's ReloadModifiedDocuments).
    private var watcher: FileWatcher?

    var onClose: (() -> Void)?

    /// What presentation mode changed, so leaving it restores everything.
    private struct PresentationState {
        let view: ViewState
        let sidebarCollapsed: Bool
        let toolbarVisible: Bool
        let toolbarAutosaves: Bool
        let wasFullScreen: Bool
    }

    /// Debug snapshots turn off `restoresFrame` so their size doesn't depend on
    /// the user's last window, and `persistsState` so runs don't leave per-file state behind.
    init(
        library: Library, thumbnails: ThumbnailStore, host: MainWindowHost, restoresFrame: Bool = true,
        persistsState: Bool = true
    ) {
        self.library = library
        self.thumbnails = thumbnails
        self.host = host
        self.persistsState = persistsState
        let window = ReaderWindow(
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
        window.onDrop = { [weak self] urls in self?.openDropped(urls) ?? false }
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange(_:)), name: .settingsDidChange, object: nil)

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = toolbarController
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        // Debug snapshots must not change (or depend on) the user's toolbar setup.
        toolbar.autosavesConfiguration = restoresFrame
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
    var isSettled: Bool {
        !isChangingFullScreen && (canvas?.isSettled ?? true) && (currentDocument?.thumbnails.isIdle ?? true)
    }

    /// Entering or leaving full screen animates; the layout is final only after it.
    private var isChangingFullScreen = false

    func showHome() {
        if presentation != nil { togglePresentation(nil) }
        saveDocumentState()
        stopWatching()
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

    /// Shows a document. Without an explicit `state` it comes back the way it
    /// was last left (SumatraPDF's RememberStatePerDocument).
    func show(_ engine: any DocumentEngine, state: ViewState? = nil, countsAsOpen: Bool = true) {
        saveDocumentState()
        stopWatching()
        if let url = documentURL, url != engine.url { host?.documentDidClose(url) }

        let settings = library.settings
        let record = settings.rememberStatePerDocument ? library.record(for: engine.url.path) : nil
        let controller = DocumentViewController(
            engine: engine, library: library, state: state ?? record?.state ?? settings.initialViewState,
            sidebarVisible: record?.sidebarVisible ?? currentDocument.map { !$0.isSidebarCollapsed })
        controller.onStateChange = { [weak self] in self?.toolbarController.update() }
        controller.canvas.onSearchStatus = { [weak self] status in self?.window?.subtitle = status ?? "" }
        currentDocument = controller
        setContent(controller)
        window?.title = engine.url.lastPathComponent
        window?.representedURL = engine.url
        toolbarController.update()
        host?.documentDidOpen(engine, countsAsOpen: countsAsOpen)
        watch(engine.url)
    }

    /// Remembers page, zoom, layout and sidebar for the shown document.
    func saveDocumentState() {
        guard persistsState, library.settings.rememberStatePerDocument, let document = currentDocument, let canvas,
            canvas.layout.pageFrames.count > 0
        else { return }
        library.saveViewState(
            canvas.viewState, sidebarVisible: !document.isSidebarCollapsed, for: document.engine.url.path)
    }

    // MARK: - Reload on change

    private func watch(_ url: URL) {
        guard library.settings.reloadModifiedDocuments else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.reloadAfterChange(of: url) }
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// Turning "reload on change" on or off in Settings applies to open documents too.
    @objc private func settingsDidChange(_ note: Notification) {
        stopWatching()
        if let url = documentURL { watch(url) }
    }

    /// Reopens the changed file keeping the view. A file caught mid-write
    /// fails to open silently; the next change event tries again.
    private func reloadAfterChange(of url: URL) {
        guard documentURL == url, let state = canvas?.viewState,
            let engine = try? DocumentOpener.open(url)
        else { return }
        show(engine, state: state, countsAsOpen: false)
        flash("Reloaded: the file changed on disk")
    }

    /// Documents dropped on the window open like Open… from it: the first
    /// replaces a home page, the rest become tabs. False if none could be opened.
    @discardableResult
    func openDropped(_ urls: [URL]) -> Bool {
        let documents = urls.filter(DocumentOpener.canOpen)
        var opened = false
        for url in documents {
            opened = host?.open(url, from: self) != nil || opened
        }
        return opened
    }

    /// Sends a menu action through this window's responder chain, starting at
    /// the canvas (or the window when showing home), regardless of focus.
    func perform(_ action: Selector) -> Bool {
        let start: NSResponder? = canvas ?? window?.firstResponder ?? window
        return start?.sendThroughChain(action) ?? false
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
        show(engine, state: state, countsAsOpen: false)
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

    /// ⌘F: the toolbar's search field, or a prompt when the toolbar is hidden.
    @objc func showFind(_ sender: Any?) {
        guard let canvas else { return }
        if window?.toolbar?.isVisible == true, toolbarController.focusSearch() { return }
        guard let text = prompt("Find", message: "Text to find:") else { return }
        canvas.find(text, forward: true)
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

    // MARK: - Print and properties

    @objc func printDocument(_ sender: Any?) {
        guard let engine = currentDocument?.engine, let window else { return }
        PrintView.run(engine: engine, title: engine.url.lastPathComponent, for: window)
    }

    private var properties: PropertiesWindowController?

    @objc func showProperties(_ sender: Any?) {
        guard let engine = currentDocument?.engine else { return }
        properties?.close()
        let controller = PropertiesWindowController(engine: engine)
        properties = controller
        controller.showWindow(nil)
    }

    // MARK: - Command palette

    @objc func showCommandPalette(_ sender: Any?) { showPalette(nil) }
    @objc func showPaletteTabs(_ sender: Any?) { showPalette(.tabs) }
    @objc func showPaletteHistory(_ sender: Any?) { showPalette(.history) }
    @objc func showPaletteFavorites(_ sender: Any?) { showPalette(.favorites) }
    @objc func showPaletteOutline(_ sender: Any?) { showPalette(.outline) }

    /// Opens the palette; `text` pre-fills the filter (debug hook uses it).
    func showPalette(_ prefix: PaletteQuery.Source?, text: String? = nil) {
        guard let window else { return }
        CommandPalette.show(items: paletteItems(), prefix: prefix, text: text, over: window)
    }

    /// Gathered while this window is key, so command availability is the document's.
    private func paletteItems() -> [PaletteItem] {
        var items: [PaletteItem] = []
        let paletteCommands: Set<String> = [
            "CmdCommandPalette", "CmdNavigateTabs", "CmdNavigateHistory", "CmdNavigateFavorites",
            "CmdNavigateTableOfContents",
        ]
        for command in CommandTable.all where !paletteCommands.contains(command.id) {
            let action = Selector("\(command.action):")
            guard let target = (window?.firstResponder ?? window)?.chainTarget(for: action) else { continue }
            items.append(
                PaletteItem(
                    source: .commands, title: command.title, detail: command.shortcuts.first?.display ?? "",
                    symbol: "command", perform: { NSApp.sendAction(action, to: target, from: nil) }))
        }

        for controller in NSApp.windows.compactMap({ $0.windowController as? MainWindowController }) {
            guard let url = controller.documentURL else { continue }
            items.append(
                PaletteItem(
                    source: .tabs, title: url.lastPathComponent, detail: url.deletingLastPathComponent().path,
                    symbol: "macwindow", perform: { controller.window?.makeKeyAndOrderFront(nil) }))
        }

        for record in library.recent(limit: 50) where FileManager.default.fileExists(atPath: record.path) {
            let url = URL(fileURLWithPath: record.path)
            items.append(
                PaletteItem(
                    source: .history, title: url.lastPathComponent, detail: url.deletingLastPathComponent().path,
                    symbol: "clock", perform: { [weak self] in self.map { _ = $0.host?.open(url, from: $0) } }))
        }

        for favorite in library.favorites {
            let url = URL(fileURLWithPath: favorite.path)
            let detail = "\(url.lastPathComponent) · page \(favorite.page + 1)"
            items.append(
                PaletteItem(
                    source: .favorites, title: favorite.name, detail: detail,
                    symbol: "star", perform: { [weak self] in self?.openFavorite(favorite) }))
        }

        if let document = currentDocument {
            func add(_ outline: [OutlineItem], depth: Int) {
                for entry in outline {
                    let page = entry.destination.flatMap { if case .page(let p, _) = $0 { p + 1 } else { nil } }
                    let title = String(repeating: "  ", count: depth) + entry.title.trimmingCharacters(in: .whitespaces)
                    if let destination = entry.destination {
                        items.append(
                            PaletteItem(
                                source: .outline, title: title, detail: page.map { "page \($0)" } ?? "",
                                symbol: "list.bullet.indent",
                                perform: { [weak document] in document?.canvas.go(to: destination) }))
                    }
                    add(entry.children, depth: depth + 1)
                }
            }
            add(document.engine.outline(), depth: 0)
        }
        return items
    }

    private func openFavorite(_ favorite: Favorite) {
        let url = URL(fileURLWithPath: favorite.path)
        if documentURL == url {
            canvas?.jump(toPage: favorite.page)
            return
        }
        guard let target = host?.open(url, from: self) else { return }
        // The new document lays out once its window appears; jump right after.
        DispatchQueue.main.async { target.canvas?.jump(toPage: favorite.page) }
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
            window.toolbar?.autosavesConfiguration = saved.toolbarAutosaves
            if !saved.wasFullScreen && window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        } else {
            let canvas = document.canvas
            presentation = PresentationState(
                view: canvas.viewState, sidebarCollapsed: document.isSidebarCollapsed,
                toolbarVisible: window.toolbar?.isVisible ?? true,
                toolbarAutosaves: window.toolbar?.autosavesConfiguration ?? false,
                wasFullScreen: window.styleMask.contains(.fullScreen))
            document.isSidebarCollapsed = true
            // Hiding the toolbar for the presentation is not a preference to remember.
            window.toolbar?.autosavesConfiguration = false
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
        saveDocumentState()
        stopWatching()
        if let url = documentURL { host?.documentDidClose(url) }
        onClose?()
    }

    func windowWillEnterFullScreen(_ notification: Notification) { isChangingFullScreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) { isChangingFullScreen = false }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { isChangingFullScreen = false }
    func windowWillExitFullScreen(_ notification: Notification) { isChangingFullScreen = true }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { isChangingFullScreen = false }

    func windowDidExitFullScreen(_ notification: Notification) {
        isChangingFullScreen = false
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
