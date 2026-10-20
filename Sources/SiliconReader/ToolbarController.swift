import AppKit
import ReaderCore

extension NSToolbarItem.Identifier {
    static let open = Self("open")
    static let print = Self("print")
    static let pageNumber = Self("pageNumber")
    static let previousPage = Self("previousPage")
    static let nextPage = Self("nextPage")
    static let back = Self("back")
    static let forward = Self("forward")
    static let fitWidthContinuous = Self("fitWidthContinuous")
    static let fitPageSingle = Self("fitPageSingle")
    static let rotateLeft = Self("rotateLeft")
    static let rotateRight = Self("rotateRight")
    static let zoomOut = Self("zoomOut")
    static let zoom = Self("zoom")
    static let zoomIn = Self("zoomIn")
    static let find = Self("find")
}

/// SumatraPDF's toolbar (src/shared/ToolbarCommon.cpp, gToolbarButtons) in the
/// same order, minus Read Aloud and Edit PDF. Icons are SF Symbols.
@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate {
    private weak var windowController: MainWindowController?
    private let pageField = NSTextField()
    private let pageTotal = NSTextField(labelWithString: "")
    private let zoomBox = NSComboBox()

    init(windowController: MainWindowController) {
        self.windowController = windowController
        super.init()
        configureControls()
    }

    private struct Button {
        let label: String
        let symbol: String
        let action: Selector
    }

    private static let buttons: [NSToolbarItem.Identifier: Button] = [
        .open: Button(label: "Open", symbol: "folder", action: #selector(AppDelegate.openDocument(_:))),
        .print: Button(label: "Print", symbol: "printer", action: #selector(PendingCommands.printDocument(_:))),
        .previousPage: Button(
            label: "Previous Page", symbol: "chevron.up", action: #selector(DocumentView.goToPreviousPage(_:))),
        .nextPage: Button(label: "Next Page", symbol: "chevron.down", action: #selector(DocumentView.goToNextPage(_:))),
        .back: Button(label: "Back", symbol: "arrow.backward", action: #selector(DocumentView.navigateBack(_:))),
        .forward: Button(
            label: "Forward", symbol: "arrow.forward", action: #selector(DocumentView.navigateForward(_:))),
        .fitWidthContinuous: Button(
            label: "Fit Width and Show Pages Continuously", symbol: "arrow.left.and.right.text.vertical",
            action: #selector(DocumentView.fitWidthContinuous(_:))),
        .fitPageSingle: Button(
            label: "Fit a Single Page", symbol: "doc", action: #selector(DocumentView.fitPageSingle(_:))),
        .rotateLeft: Button(
            label: "Rotate Left", symbol: "rotate.left", action: #selector(DocumentView.rotateLeft(_:))),
        .rotateRight: Button(
            label: "Rotate Right", symbol: "rotate.right", action: #selector(DocumentView.rotateRight(_:))),
        .zoomOut: Button(
            label: "Zoom Out", symbol: "minus.magnifyingglass", action: #selector(DocumentView.zoomOut(_:))),
        .zoomIn: Button(label: "Zoom In", symbol: "plus.magnifyingglass", action: #selector(DocumentView.zoomIn(_:))),
        .find: Button(label: "Find", symbol: "magnifyingglass", action: #selector(PendingCommands.showFind(_:))),
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .open, .print, .space, .pageNumber, .previousPage, .nextPage, .space, .back, .forward,
            .flexibleSpace, .fitWidthContinuous, .fitPageSingle, .rotateLeft, .rotateRight, .zoomOut, .zoom, .zoomIn,
            .space, .find,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if let button = Self.buttons[identifier] {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = button.label
            item.paletteLabel = button.label
            item.toolTip = button.label
            item.image = NSImage(systemSymbolName: button.symbol, accessibilityDescription: button.label)
            item.action = button.action
            item.isBordered = true
            return item
        }
        switch identifier {
        case .pageNumber:
            return viewItem(identifier, label: "Page", view: pageStack())
        case .zoom:
            return viewItem(identifier, label: "Zoom", view: zoomBox)
        default:
            return nil
        }
    }

    private func viewItem(_ identifier: NSToolbarItem.Identifier, label: String, view: NSView) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = view
        return item
    }

    // MARK: - Page number and zoom controls

    private func configureControls() {
        pageField.alignment = .right
        pageField.target = self
        pageField.action = #selector(pageEntered(_:))
        pageField.translatesAutoresizingMaskIntoConstraints = false
        pageField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        pageField.toolTip = "Go to page"
        pageTotal.textColor = .secondaryLabelColor
        // The label starts empty; reserve room for "/ 9999" so the toolbar item isn't sized to zero.
        pageTotal.translatesAutoresizingMaskIntoConstraints = false
        pageTotal.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let levels = Zoom.levels.reversed().map { UserInput.format(percent: $0) }
        zoomBox.addItems(withObjectValues: UserInput.fitNames.map(\.name) + levels)
        zoomBox.numberOfVisibleItems = 16
        zoomBox.completes = false
        zoomBox.target = self
        zoomBox.action = #selector(zoomEntered(_:))
        zoomBox.translatesAutoresizingMaskIntoConstraints = false
        zoomBox.widthAnchor.constraint(equalToConstant: 112).isActive = true
        zoomBox.toolTip = "Zoom"
    }

    private func pageStack() -> NSView {
        let stack = NSStackView(views: [pageField, pageTotal])
        stack.spacing = 4
        return stack
    }

    /// Refreshes the page and zoom controls from the current document.
    func update() {
        guard let canvas = windowController?.canvas else {
            pageField.stringValue = ""
            pageTotal.stringValue = ""
            zoomBox.stringValue = ""
            pageField.isEnabled = false
            zoomBox.isEnabled = false
            return
        }
        pageField.isEnabled = true
        zoomBox.isEnabled = true
        let page = canvas.currentPage
        if pageField.currentEditor() == nil {
            pageField.stringValue = canvas.engine.pageLabel(at: page) ?? String(page + 1)
        }
        pageTotal.stringValue = "/ \(canvas.pageCount)"
        if zoomBox.currentEditor() == nil {
            zoomBox.stringValue =
                UserInput.fitNames.first { $0.zoom == canvas.zoom }?.name
                ?? UserInput.format(percent: canvas.layout.zoomPercent)
        }
    }

    /// Puts the cursor in the page box; false if it isn't on the toolbar.
    func focusPageField() -> Bool {
        focus(pageField)
    }

    func focusZoomBox() -> Bool {
        focus(zoomBox)
    }

    private func focus(_ control: NSControl) -> Bool {
        guard let window = windowController?.window, control.window === window, control.isEnabled else { return false }
        window.makeFirstResponder(control)
        control.currentEditor()?.selectAll(nil)
        return true
    }

    @objc private func pageEntered(_ sender: NSTextField) {
        guard let canvas = windowController?.canvas else { return }
        let engine = canvas.engine
        if let page = UserInput.page(sender.stringValue, pageCount: canvas.pageCount, label: engine.pageLabel(at:)) {
            canvas.jump(toPage: page)
        } else {
            NSSound.beep()
        }
        windowController?.window?.makeFirstResponder(canvas)
        update()
    }

    @objc private func zoomEntered(_ sender: NSComboBox) {
        guard let canvas = windowController?.canvas else { return }
        if let zoom = UserInput.zoom(sender.stringValue) {
            canvas.setZoom(zoom)
        } else {
            NSSound.beep()
        }
        windowController?.window?.makeFirstResponder(canvas)
        update()
    }
}
