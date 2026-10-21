import AppKit
import ReaderCore

extension Notification.Name {
    /// Posted after the Settings window changed `Library.settings`.
    static let settingsDidChange = Notification.Name("SiliconReaderSettingsDidChange")
}

/// Settings (⌘,): the essentials of SumatraPDF's Options dialog. Changes apply
/// at once, as macOS settings windows do; the default view affects documents
/// opened afterwards that have no remembered state.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let library: Library
    private let layoutPopup = NSPopUpButton()
    private let continuousBox = NSButton(checkboxWithTitle: "Continuous", target: nil, action: nil)
    private let zoomPopup = NSPopUpButton()
    private let rememberBox = NSButton(
        checkboxWithTitle: "Remember page, zoom and layout of each document", target: nil, action: nil)
    private let restoreBox = NSButton(
        checkboxWithTitle: "Reopen the last session's documents at launch", target: nil, action: nil)
    private let reloadBox = NSButton(
        checkboxWithTitle: "Reload documents when their file changes on disk", target: nil, action: nil)

    private static let arrangements: [(String, PageArrangement)] = [
        ("Single Page", .single), ("Facing", .facing), ("Book View", .book),
    ]
    private static let percents: [CGFloat] = [50, 75, 100, 125, 150, 200]

    /// Zoom popup entries: Sumatra's fit modes, then common percentages.
    private var zoomChoices: [(String, Zoom)] = []

    init(library: Library) {
        self.library = library
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Settings"
        super.init(window: window)
        window.contentView = makeContent()
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)
        window.center()
        load(library.settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        for (title, _) in Self.arrangements { layoutPopup.addItem(withTitle: title) }
        for control in [layoutPopup, continuousBox, zoomPopup, rememberBox, restoreBox, reloadBox] {
            control.target = self
            control.action = #selector(changed(_:))
        }

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let empty = NSGridCell.emptyContentView
        let grid = NSGridView(views: [
            [label("Default layout:"), layoutPopup],
            [empty, continuousBox],
            [label("Default zoom:"), zoomPopup],
            [label("Documents:"), rememberBox],
            [empty, restoreBox],
            [empty, reloadBox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        // Space between the view group and the document group.
        grid.row(at: 3).topPadding = 12

        let hint = NSTextField(
            wrappingLabelWithString: "The default layout and zoom apply to documents opened for the first time.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = 420

        let stack = NSStackView(views: [grid, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    private func load(_ settings: Settings) {
        let arrangement = Self.arrangements.firstIndex { $0.1 == settings.defaultMode.arrangement } ?? 0
        layoutPopup.selectItem(at: arrangement)
        continuousBox.state = settings.defaultMode.continuous ? .on : .off

        zoomChoices =
            UserInput.fitNames.map { ($0.name, $0.zoom) }
            + Self.percents.map { (UserInput.format(percent: $0), Zoom.percent($0)) }
        if !zoomChoices.contains(where: { $0.1 == settings.defaultZoom }), case .percent(let p) = settings.defaultZoom {
            zoomChoices.append((UserInput.format(percent: p), settings.defaultZoom))
        }
        zoomPopup.removeAllItems()
        for (title, _) in zoomChoices { zoomPopup.addItem(withTitle: title) }
        zoomPopup.menu?.insertItem(.separator(), at: UserInput.fitNames.count)
        if let index = zoomChoices.firstIndex(where: { $0.1 == settings.defaultZoom }) {
            zoomPopup.selectItem(withTitle: zoomChoices[index].0)
        }

        rememberBox.state = settings.rememberStatePerDocument ? .on : .off
        restoreBox.state = settings.restoreSession ? .on : .off
        reloadBox.state = settings.reloadModifiedDocuments ? .on : .off
    }

    @objc private func changed(_ sender: Any?) {
        var settings = library.settings
        let arrangement = Self.arrangements[max(0, layoutPopup.indexOfSelectedItem)].1
        settings.defaultMode = ViewMode(arrangement: arrangement, continuous: continuousBox.state == .on)
        if let title = zoomPopup.titleOfSelectedItem, let zoom = zoomChoices.first(where: { $0.0 == title })?.1 {
            settings.defaultZoom = zoom
        }
        settings.rememberStatePerDocument = rememberBox.state == .on
        settings.restoreSession = restoreBox.state == .on
        settings.reloadModifiedDocuments = reloadBox.state == .on
        library.settings = settings
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}
