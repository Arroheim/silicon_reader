import AppKit
import ReaderCore

/// The sidebar's page thumbnails: one row per page with its image and label.
///
/// Images render in the background one at a time, visible rows first; rows
/// scrolled away before their turn are skipped and asked for again when they
/// come back. The current page is selected and kept in view while reading.
@MainActor
final class PageThumbnailsController: NSObject {
    /// Thumbnail width in points.
    static let width: CGFloat = 120
    private static let labelHeight: CGFloat = 18
    private static let padding: CGFloat = 8

    private let engine: any DocumentEngine
    private let onSelect: (Int) -> Void
    private let pageSizes: [CGSize]
    let tableView = NSTableView()
    private(set) lazy var scrollView: NSScrollView = makeScrollView()

    private var images: [Int: NSImage] = [:]
    private var requested = Set<Int>()
    private var renderTask: Task<Void, Never>?
    /// Set while the selection follows the canvas, so it isn't taken for a click.
    private var isSyncing = false

    /// No thumbnail is waiting to render (debug snapshot hook).
    var isIdle: Bool { renderTask == nil }

    init(engine: any DocumentEngine, onSelect: @escaping (Int) -> Void) {
        self.engine = engine
        self.onSelect = onSelect
        pageSizes = (0..<engine.pageCount).map { (try? engine.pageSize(at: $0)) ?? CGSize(width: 612, height: 792) }
        super.init()
    }

    private func makeScrollView() -> NSScrollView {
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    /// Selects `page` and scrolls it into view without navigating.
    func show(page: Int) {
        guard (0..<pageSizes.count).contains(page), tableView.selectedRow != page else { return }
        isSyncing = true
        tableView.selectRowIndexes(IndexSet(integer: page), byExtendingSelection: false)
        tableView.scrollRowToVisible(page)
        isSyncing = false
    }

    var selectedPage: Int? { tableView.selectedRow >= 0 ? tableView.selectedRow : nil }

    /// What a click on the thumbnail of `page` does (the control channel uses it too).
    func activate(page: Int) {
        guard (0..<pageSizes.count).contains(page) else { return }
        show(page: page)
        onSelect(page)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        if row >= 0 { onSelect(row) }
    }

    // MARK: - Rendering

    private func thumbnailSize(_ page: Int) -> CGSize {
        let size = pageSizes[page]
        let height = size.width > 0 ? Self.width * size.height / size.width : Self.width
        return CGSize(width: Self.width, height: min(height, Self.width * 3))
    }

    private func request(_ page: Int) {
        guard images[page] == nil else { return }
        requested.insert(page)
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while let (engine, page, scale) = self?.next() {
                let image = await Task.detached(priority: .utility) {
                    try? engine.render(page: page, scale: scale)
                }.value
                self?.finished(page, image)
            }
            self?.renderTask = nil
        }
    }

    /// The first requested page that is still on screen; forgets the others.
    private func next() -> (any DocumentEngine, Int, CGFloat)? {
        let visible = tableView.rows(in: tableView.visibleRect)
        requested = requested.filter { visible.contains($0) }
        guard let page = requested.min() else { return nil }
        requested.remove(page)
        let pixels = Self.width * (tableView.window?.backingScaleFactor ?? 2)
        let width = max(pageSizes[page].width, 1)
        return (engine, page, pixels / width)
    }

    private func finished(_ page: Int, _ image: CGImage?) {
        let size = thumbnailSize(page)
        // A page that fails to render keeps a blank white thumbnail.
        images[page] = image.map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        if let cell = tableView.view(atColumn: 0, row: page, makeIfNecessary: false) as? ThumbnailCell {
            cell.image = images[page]
        }
    }
}

extension PageThumbnailsController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        pageSizes.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        thumbnailSize(row).height + Self.labelHeight + Self.padding
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("thumbnail")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ThumbnailCell ?? ThumbnailCell()
        cell.identifier = identifier
        cell.imageSize = thumbnailSize(row)
        cell.image = images[row]
        cell.label = engine.pageLabel(at: row) ?? String(row + 1)
        if images[row] == nil { request(row) }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Keyboard moves in the list navigate like clicks do.
        guard !isSyncing, tableView.clickedRow < 0, let page = selectedPage else { return }
        onSelect(page)
    }
}

/// A page image with a white placeholder while it renders, and the page label under it.
final class ThumbnailCell: NSTableCellView {
    private let pageImage = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    var image: NSImage? {
        get { pageImage.image }
        set { pageImage.image = newValue }
    }

    var label: String {
        get { labelField.stringValue }
        set { labelField.stringValue = newValue }
    }

    var imageSize: CGSize = .zero {
        didSet {
            widthConstraint?.constant = imageSize.width
            heightConstraint?.constant = imageSize.height
        }
    }

    init() {
        super.init(frame: .zero)
        pageImage.imageScaling = .scaleProportionallyUpOrDown
        pageImage.wantsLayer = true
        pageImage.layer?.backgroundColor = NSColor.white.cgColor
        pageImage.layer?.borderColor = NSColor.separatorColor.cgColor
        pageImage.layer?.borderWidth = 1
        labelField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .center
        for view in [pageImage, labelField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let width = pageImage.widthAnchor.constraint(equalToConstant: 0)
        let height = pageImage.heightAnchor.constraint(equalToConstant: 0)
        widthConstraint = width
        heightConstraint = height
        NSLayoutConstraint.activate([
            width, height,
            pageImage.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            pageImage.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelField.topAnchor.constraint(equalTo: pageImage.bottomAnchor, constant: 2),
            labelField.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
