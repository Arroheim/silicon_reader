import AppKit
import ReaderCore

/// SumatraPDF's start page: "Frequently Read" thumbnails and "Open a document…".
@MainActor
final class HomeViewController: NSViewController {
    /// SumatraPDF shows up to 10 frequently read documents.
    private static let maxItems = 10

    private let library: Library
    private let thumbnails: ThumbnailStore
    private let onOpen: (URL) -> Void
    private var records: [FileRecord] = []
    private let collectionView = NSCollectionView()
    private let emptyLabel = NSTextField(labelWithString: "Documents you open will appear here.")

    init(library: Library, thumbnails: ThumbnailStore, onOpen: @escaping (URL) -> Void) {
        self.library = library
        self.thumbnails = thumbnails
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = CanvasBackgroundView()

        // App icon is the logo (Resources/AppIcon.png, bundled as AppIcon.icns).
        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let appName = NSTextField(labelWithString: "Silicon Reader")
        appName.font = .systemFont(ofSize: 28, weight: .bold)
        let header = NSStackView(views: [logo, appName])
        header.spacing = 12

        let title = NSTextField(labelWithString: "Frequently Read")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: ThumbnailStore.width, height: ThumbnailStore.width * 1.3 + 28)
        layout.minimumInteritemSpacing = 24
        layout.minimumLineSpacing = 24
        layout.sectionInset = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(HomeItem.self, forItemWithIdentifier: HomeItem.identifier)
        collectionView.menu = contextMenu()

        let scroll = NSScrollView()
        scroll.documentView = collectionView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let open = NSButton(title: "Open a document…", target: self, action: #selector(openDocument(_:)))
        open.bezelStyle = .push
        open.keyEquivalent = "\r"

        emptyLabel.textColor = .secondaryLabelColor

        for view in [header, title, scroll, open, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            scroll.bottomAnchor.constraint(equalTo: open.topAnchor, constant: -16),
            open.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            open.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            emptyLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
        ])
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        records = library.frequentlyRead(limit: Self.maxItems)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        emptyLabel.isHidden = !records.isEmpty
        collectionView.reloadData()
    }

    @objc func openDocument(_ sender: Any?) {
        NSApp.sendAction(#selector(AppDelegate.openDocument(_:)), to: nil, from: self)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openClicked(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove from History", action: #selector(removeFromHistory(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    private var clickedRecord: FileRecord? {
        let point = collectionView.convert(collectionView.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        if let index = collectionView.indexPathForItem(at: point)?.item, index < records.count {
            return records[index]
        }
        return collectionView.selectionIndexPaths.first.map { records[$0.item] }
    }

    @objc private func openClicked(_ sender: Any?) {
        if let record = clickedRecord { onOpen(URL(fileURLWithPath: record.path)) }
    }

    @objc private func showInFinder(_ sender: Any?) {
        if let record = clickedRecord {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)])
        }
    }

    @objc private func removeFromHistory(_ sender: Any?) {
        guard let record = clickedRecord else { return }
        library.forget(record.path)
        reload()
    }
}

extension HomeViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        records.count
    }

    func collectionView(
        _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: HomeItem.identifier, for: indexPath)
        let record = records[indexPath.item]
        if let home = item as? HomeItem {
            let title = URL(fileURLWithPath: record.path).lastPathComponent
            home.configure(title: title, image: thumbnails.thumbnail(for: record.path))
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item else { return }
        collectionView.deselectAll(nil)
        onOpen(URL(fileURLWithPath: records[index].path))
    }
}

/// Fills with the canvas color; drawn rather than layer-backed so it follows
/// light/dark appearance changes.
final class CanvasBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DocumentView.canvasColor.setFill()
        dirtyRect.fill()
    }
}

/// One thumbnail with the file name under it.
@MainActor
final class HomeItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeItem")

    private let thumbnail = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView()
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.imageAlignment = .alignBottom
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        for view in [thumbnail, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: root.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            thumbnail.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    func configure(title: String, image: NSImage?) {
        label.stringValue = title
        thumbnail.image = image ?? NSImage(systemSymbolName: "doc", accessibilityDescription: title)
        thumbnail.toolTip = title
    }
}
