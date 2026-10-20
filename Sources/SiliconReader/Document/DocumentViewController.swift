import AppKit
import ReaderCore

/// One open document: sidebar (bookmarks, favorites) next to the canvas.
@MainActor
final class DocumentViewController: NSSplitViewController {
    let engine: any DocumentEngine
    let canvas: DocumentView
    private let library: Library
    private let sidebar: SidebarViewController
    private let canvasScroll = CanvasScrollView()

    /// Forwarded from the canvas: page, zoom or mode changed.
    var onStateChange: (() -> Void)?

    init(engine: any DocumentEngine, library: Library) {
        self.engine = engine
        self.library = library
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
        let canvasController = NSViewController()
        canvasController.view = canvasScroll

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 480
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = !sidebar.hasContent
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: canvasController))

        let clip = canvasScroll.contentView
        clip.postsFrameChangedNotifications = true
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipFrameChanged), name: NSView.frameDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsChanged), name: NSView.boundsDidChangeNotification, object: clip)
        canvas.onStateChange = { [weak self] in self?.onStateChange?() }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        canvas.viewportDidResize()
        view.window?.makeFirstResponder(canvas)
    }

    @objc private func clipFrameChanged(_ note: Notification) {
        canvas.viewportDidResize()
    }

    @objc private func clipBoundsChanged(_ note: Notification) {
        canvas.viewportDidScroll()
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
        if let item = splitViewItems.first, item.isCollapsed {
            item.animator().isCollapsed = false
        }
    }
}
