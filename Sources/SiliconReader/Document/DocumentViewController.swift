import AppKit
import ReaderCore

/// One open document: sidebar (bookmarks, favorites) next to the canvas,
/// plus SumatraPDF's on-canvas info (page info, cursor position).
@MainActor
final class DocumentViewController: NSSplitViewController {
    let engine: any DocumentEngine
    let canvas: DocumentView
    private let library: Library
    private let sidebar: SidebarViewController
    private let canvasScroll = CanvasScrollView()
    private let hud = HUDLabel()
    /// Restored once the canvas has a size (reload, duplicate window, saved state).
    private var pendingState: ViewState?
    /// Saved sidebar visibility; nil means "show it if there is anything to show".
    private let sidebarVisible: Bool?

    private var showsPageInfo = false
    private var showsCursorPosition = false
    private var pointer: (page: Int, point: CGPoint)?

    /// Forwarded from the canvas: page, zoom or mode changed.
    var onStateChange: (() -> Void)?

    init(engine: any DocumentEngine, library: Library, state: ViewState? = nil, sidebarVisible: Bool? = nil) {
        self.engine = engine
        self.library = library
        self.pendingState = state
        self.sidebarVisible = sidebarVisible
        canvas = DocumentView(engine: engine)
        var navigate: (Destination) -> Void = { _ in }
        sidebar = SidebarViewController(engine: engine, library: library, onNavigate: { navigate($0) })
        super.init(nibName: nil, bundle: nil)
        navigate = { [weak self] destination in
            guard let self else { return }
            canvas.go(to: destination)
            view.window?.makeFirstResponder(canvas)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true
        canvasScroll.autohidesScrollers = true
        canvasScroll.drawsBackground = true
        canvasScroll.backgroundColor = DocumentView.canvasColor
        canvasScroll.documentView = canvas

        // The HUD floats over the scroll view, so it stays put while pages scroll.
        // The canvas starts below the toolbar: with Liquid Glass (macOS 26+ SDK) a
        // full-size content view would draw pages over the title and under the
        // floating toolbar buttons.
        let container = NSView()
        for view in [canvasScroll, hud] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            canvasScroll.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            canvasScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            canvasScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvasScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hud.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 12),
            hud.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        hud.isHidden = true
        let canvasController = NSViewController()
        canvasController.view = container

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 480
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = !(sidebarVisible ?? true) || !sidebar.hasContent
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: canvasController))

        let clip = canvasScroll.contentView
        clip.postsFrameChangedNotifications = true
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipFrameChanged), name: NSView.frameDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsChanged), name: NSView.boundsDidChangeNotification, object: clip)
        canvas.onStateChange = { [weak self] in
            guard let self else { return }
            updateHUD()
            sidebar.currentPageChanged(canvas.currentPage)
            onStateChange?()
        }
        canvas.onPointerMoved = { [weak self] pointer in
            self?.pointer = pointer
            self?.updateHUD()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        canvas.viewportDidResize()
        if let state = pendingState {
            pendingState = nil
            canvas.apply(state)
        }
        sidebar.currentPageChanged(canvas.currentPage)
        view.window?.makeFirstResponder(canvas)
    }

    @objc private func clipFrameChanged(_ note: Notification) {
        canvas.viewportDidResize()
    }

    @objc private func clipBoundsChanged(_ note: Notification) {
        canvas.viewportDidScroll()
    }

    var isSidebarCollapsed: Bool {
        get { splitViewItems.first?.isCollapsed ?? true }
        set { splitViewItems.first?.isCollapsed = newValue }
    }

    var sidebarMode: SidebarViewController.Mode { sidebar.mode }
    var thumbnails: PageThumbnailsController { sidebar.thumbnails }

    /// Whether the canvas reaches above the window's content layout rect, i.e.
    /// into the title bar or toolbar.
    var canvasUnderToolbar: Bool {
        guard let window = view.window else { return false }
        let frame = canvasScroll.convert(canvasScroll.bounds, to: nil)
        return frame.maxY > window.contentLayoutRect.maxY + 0.5
    }

    // MARK: - Sidebar modes

    /// ⌥⌘2: opens the sidebar on page thumbnails.
    @objc func showThumbnails(_ sender: Any?) { showSidebar(.thumbnails) }

    /// ⌥⌘3: opens the sidebar on bookmarks and favorites.
    @objc func showBookmarks(_ sender: Any?) { showSidebar(.bookmarks) }

    private func showSidebar(_ mode: SidebarViewController.Mode) {
        sidebar.show(mode)
        isSidebarCollapsed = false
        sidebar.currentPageChanged(canvas.currentPage)
    }

    // MARK: - On-canvas info

    @objc func togglePageInfo(_ sender: Any?) {
        showsPageInfo.toggle()
        updateHUD()
    }

    @objc func toggleCursorPosition(_ sender: Any?) {
        showsCursorPosition.toggle()
        updateHUD()
    }

    private func updateHUD() {
        var lines: [String] = []
        if showsPageInfo {
            let page = canvas.currentPage
            let label = engine.pageLabel(at: page).map { " (\($0))" } ?? ""
            let size = (try? engine.pageSize(at: page)).map { Self.formatSize($0) } ?? ""
            lines.append("Page \(page + 1) of \(canvas.pageCount)\(label) · \(size)")
        }
        if showsCursorPosition {
            if let pointer {
                let x = String(format: "%.1f", pointer.point.x)
                let y = String(format: "%.1f", pointer.point.y)
                lines.append("Page \(pointer.page + 1): \(x), \(y) pt")
            } else {
                lines.append("Cursor: not over a page")
            }
        }
        hud.stringValue = lines.joined(separator: "\n")
        hud.isHidden = lines.isEmpty
    }

    /// "210 × 297 mm" for metric-looking sizes, inches otherwise (Sumatra shows both systems).
    private static func formatSize(_ size: CGSize) -> String {
        let mm = { (points: CGFloat) in Int((points / 72 * 25.4).rounded()) }
        let inches = { (points: CGFloat) in String(format: "%.2f", points / 72) }
        return "\(mm(size.width)) × \(mm(size.height)) mm (\(inches(size.width)) × \(inches(size.height)) in)"
    }

    // MARK: - Focus

    /// F6: move keyboard focus between the sidebar and the canvas.
    @objc func moveFrameFocus(_ sender: Any?) {
        guard let window = view.window else { return }
        if window.firstResponder === canvas, !isSidebarCollapsed {
            sidebar.focus()
        } else {
            window.makeFirstResponder(canvas)
        }
    }

    // MARK: - Favorites

    /// SumatraPDF's "Add to favorites": asks for a name, defaulting to the page label.
    @objc func addFavorite(_ sender: Any?) {
        let page = canvas.currentPage
        let alert = NSAlert()
        alert.messageText = "Add Favorite"
        alert.informativeText = "Name for page \(engine.pageLabel(at: page) ?? String(page + 1)):"
        let defaultName = engine.pageLabel(at: page).map { "Page \($0)" } ?? "Page \(page + 1)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultName
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        library.addFavorite(Favorite(path: engine.url.path, page: page, name: name.isEmpty ? defaultName : name))
        sidebar.reload()
        if isSidebarCollapsed {
            splitViewItems.first?.animator().isCollapsed = false
        }
    }
}

extension DocumentViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePageInfo(_:)):
            item.state = showsPageInfo ? .on : .off
            return true
        case #selector(toggleCursorPosition(_:)):
            item.state = showsCursorPosition ? .on : .off
            return true
        case #selector(addFavorite(_:)), #selector(moveFrameFocus(_:)):
            return true
        case #selector(showThumbnails(_:)), #selector(showBookmarks(_:)):
            let thumbnails = item.action == #selector(showThumbnails(_:))
            let mode: SidebarViewController.Mode = thumbnails ? .thumbnails : .bookmarks
            item.state = !isSidebarCollapsed && sidebar.mode == mode ? .on : .off
            return true
        default:
            // e.g. toggleSidebar, which NSSplitViewController validates and retitles
            return super.validateUserInterfaceItem(item)
        }
    }
}

/// Small rounded label drawn over the canvas.
final class HUDLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        textColor = .white
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = 6
        alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 16, height: size.height + 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Inset the text so it doesn't touch the rounded background.
        let inset = bounds.insetBy(dx: 8, dy: 4)
        attributedStringValue.draw(in: inset)
    }
}
