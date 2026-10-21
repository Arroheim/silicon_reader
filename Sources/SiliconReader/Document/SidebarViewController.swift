import AppKit
import ReaderCore

/// A row in the sidebar outline. A class because NSOutlineView identifies items by reference.
final class SidebarNode: NSObject {
    let title: String
    let destination: Destination?
    let children: [SidebarNode]
    let isGroup: Bool
    let isExpanded: Bool
    /// Set for favorite rows, so they can be removed.
    let favoritePage: Int?

    init(
        title: String, destination: Destination? = nil, children: [SidebarNode] = [], isGroup: Bool = false,
        isExpanded: Bool = false, favoritePage: Int? = nil
    ) {
        self.title = title
        self.destination = destination
        self.children = children
        self.isGroup = isGroup
        self.isExpanded = isExpanded
        self.favoritePage = favoritePage
    }

    convenience init(_ item: OutlineItem) {
        self.init(
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines), destination: item.destination,
            children: item.children.map(SidebarNode.init), isExpanded: item.isExpanded)
    }
}

/// SumatraPDF's sidebar: the document's bookmarks (table of contents) and
/// favorites, plus page thumbnails (which Sumatra lacks), one at a time.
@MainActor
final class SidebarViewController: NSViewController {
    enum Mode: String {
        case bookmarks, thumbnails
    }

    private let engine: any DocumentEngine
    private let library: Library
    private let onNavigate: (Destination) -> Void
    private let outline: [OutlineItem]
    private var groups: [SidebarNode] = []
    private let outlineView = NSOutlineView()
    private lazy var outlineScroll = makeOutlineScroll()
    let thumbnails: PageThumbnailsController
    private let modePicker = NSSegmentedControl(
        labels: ["Bookmarks", "Thumbnails"], trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSView()

    /// Bookmarks when the document has any, thumbnails otherwise.
    private(set) var mode: Mode

    init(engine: any DocumentEngine, library: Library, onNavigate: @escaping (Destination) -> Void) {
        self.engine = engine
        self.library = library
        self.onNavigate = onNavigate
        self.outline = engine.outline()
        thumbnails = PageThumbnailsController(engine: engine) { onNavigate(.page($0)) }
        mode = .bookmarks
        super.init(nibName: nil, bundle: nil)
        groups = buildGroups()
        if groups.isEmpty { mode = .thumbnails }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Whether there are bookmarks or favorites; the sidebar starts collapsed
    /// otherwise (thumbnails alone don't open it, as Sumatra keeps it closed).
    var hasContent: Bool { !groups.isEmpty }

    override func loadView() {
        modePicker.target = self
        modePicker.action = #selector(modePicked(_:))
        modePicker.segmentStyle = .automatic
        modePicker.controlSize = .small
        for view in [modePicker, content] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        let container = NSView()
        container.addSubview(modePicker)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            modePicker.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 6),
            modePicker.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.topAnchor.constraint(equalTo: modePicker.bottomAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        reload()
        show(mode)
    }

    /// Switches between bookmarks and thumbnails.
    func show(_ mode: Mode) {
        self.mode = mode
        guard isViewLoaded else { return }
        modePicker.selectedSegment = mode == .bookmarks ? 0 : 1
        let shown = mode == .bookmarks ? outlineScroll : thumbnails.scrollView
        guard shown.superview !== content else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        shown.frame = content.bounds
        shown.autoresizingMask = [.width, .height]
        content.addSubview(shown)
    }

    @objc private func modePicked(_ sender: NSSegmentedControl) {
        show(sender.selectedSegment == 0 ? .bookmarks : .thumbnails)
    }

    /// Follows the canvas's current page in the thumbnails.
    func currentPageChanged(_ page: Int) {
        thumbnails.show(page: page)
    }

    private func makeOutlineScroll() -> NSScrollView {
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.floatsGroupRows = false
        outlineView.autoresizesOutlineColumn = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        outlineView.menu = contextMenu()

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func reload() {
        groups = buildGroups()
        guard isViewLoaded else { return }
        _ = outlineScroll
        outlineView.reloadData()
        for group in groups { expand(group) }
    }

    private func buildGroups() -> [SidebarNode] {
        var groups: [SidebarNode] = []
        if !outline.isEmpty {
            let rows = outline.map(SidebarNode.init)
            groups.append(SidebarNode(title: "Bookmarks", children: rows, isGroup: true, isExpanded: true))
        }
        let favorites = library.favorites(for: engine.url.path)
        if !favorites.isEmpty {
            let rows = favorites.map {
                SidebarNode(title: $0.name, destination: .page($0.page), favoritePage: $0.page)
            }
            groups.append(SidebarNode(title: "Favorites", children: rows, isGroup: true, isExpanded: true))
        }
        return groups
    }

    private func expand(_ node: SidebarNode) {
        guard node.isExpanded || node.isGroup else { return }
        outlineView.expandItem(node)
        for child in node.children { expand(child) }
    }

    func focus() {
        view.window?.makeFirstResponder(mode == .bookmarks ? outlineView : thumbnails.tableView)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode, let destination = node.destination
        else { return }
        onNavigate(destination)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let remove = menu.addItem(
            withTitle: "Remove from Favorites", action: #selector(removeFavorite(_:)), keyEquivalent: "")
        remove.target = self
        return menu
    }

    @objc private func removeFavorite(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let page = (outlineView.item(atRow: row) as? SidebarNode)?.favoritePage else { return }
        library.removeFavorite(path: engine.url.path, page: page)
        reload()
    }
}

extension SidebarViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(removeFavorite(_:)) else { return true }
        let row = outlineView.clickedRow
        return row >= 0 && (outlineView.item(atRow: row) as? SidebarNode)?.favoritePage != nil
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func node(_ item: Any?) -> [SidebarNode] {
        (item as? SidebarNode)?.children ?? groups
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SidebarNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.isGroup ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? SidebarNode)?.isGroup ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier(node.isGroup ? "group" : "cell")
        let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        let cell = reused ?? makeCell(identifier)
        cell.textField?.stringValue = node.title
        cell.toolTip = node.title
        return cell
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
