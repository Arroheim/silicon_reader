import AppKit
import ReaderCore

/// One row of the command palette.
struct PaletteItem {
    let source: PaletteQuery.Source
    let title: String
    /// Path, page number or shortcut, shown dimmed and searched too.
    let detail: String
    let symbol: String
    let perform: @MainActor () -> Void
}

/// SumatraPDF's command palette (Ctrl+K): a filter box over commands, tabs,
/// recent files, favorites and bookmarks, with Sumatra's prefix characters.
@MainActor
final class CommandPalette: NSObject {
    private let panel: PalettePanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let items: [PaletteItem]
    private var shown: [PaletteItem] = []
    private weak var parent: NSWindow?
    /// Keeps the palette alive while it is on screen.
    private static var current: CommandPalette?

    private init(items: [PaletteItem], text: String, parent: NSWindow) {
        self.items = items
        self.parent = parent
        panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 380),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        buildUI()
        field.stringValue = text
        filter()
    }

    /// Shows the palette over `window` with items gathered beforehand (so
    /// command availability reflects the document window, not the palette).
    /// `prefix` pre-selects a list; `text` replaces the whole filter.
    static func show(items: [PaletteItem], prefix: PaletteQuery.Source?, text: String? = nil, over window: NSWindow) {
        current?.dismiss()
        let initial = text ?? prefix.map { String($0.rawValue) } ?? ""
        let palette = CommandPalette(items: items, text: initial, parent: window)
        current = palette
        let frame = window.frame
        palette.panel.setFrameOrigin(
            NSPoint(x: frame.midX - palette.panel.frame.width / 2, y: frame.maxY - palette.panel.frame.height - 90))
        window.addChildWindow(palette.panel, ordered: .above)
        palette.panel.makeKeyAndOrderFront(nil)
        palette.panel.makeFirstResponder(palette.field)
        palette.field.currentEditor()?.moveToEndOfDocument(nil)
    }

    private func buildUI() {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.hidesOnDeactivate = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.onResignKey = { [weak self] in self?.dismiss() }

        field.placeholderString = "Type a command, or > commands  @ tabs  # recent  $ favorites  % bookmarks"
        field.font = .systemFont(ofSize: 16)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(performSelected)
        table.backgroundColor = .clear

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        for view in [field, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
        ])
        panel.contentView = background
    }

    private func filter() {
        let query = PaletteQuery(field.stringValue)
        let pool =
            query.source.map { source in items.filter { $0.source == source } }
            ?? items.filter { [.commands, .tabs, .history].contains($0.source) }
        shown = query.filter(pool, title: \.title, detail: \.detail)
        table.reloadData()
        if !shown.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    @objc private func performSelected() {
        let row = table.selectedRow
        guard shown.indices.contains(row) else { return NSSound.beep() }
        let item = shown[row]
        let parent = parent
        dismiss()
        parent?.makeKeyAndOrderFront(nil)
        item.perform()
    }

    private func dismiss() {
        guard Self.current === self else { return }
        Self.current = nil
        panel.onResignKey = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func moveSelection(by delta: Int) {
        guard !shown.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), shown.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }
}

extension CommandPalette: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filter()
    }

    /// ↑/↓ move through the list while typing; Return runs; Esc closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): moveSelection(by: -10)
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): moveSelection(by: 10)
        case #selector(NSResponder.insertNewline(_:)): performSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            let parent = parent
            dismiss()
            parent?.makeKeyAndOrderFront(nil)
        default: return false
        }
        return true
    }
}

extension CommandPalette: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = shown[row]
        let reused = tableView.makeView(withIdentifier: PaletteCell.identifier, owner: self) as? PaletteCell
        let cell = reused ?? PaletteCell()
        cell.configure(item)
        return cell
    }
}

/// Icon, title and a dimmed detail on the right.
@MainActor
final class PaletteCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PaletteCell")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.alignment = .right
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.contentTintColor = .secondaryLabelColor
        for view in [icon, title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ item: PaletteItem) {
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        title.stringValue = item.title
        detail.stringValue = item.detail
    }
}

/// A titled panel that can become key (for typing) and reports losing focus.
final class PalettePanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
