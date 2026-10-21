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
    static let findPrevious = Self("findPrevious")
    static let findNext = Self("findNext")
}

/// SumatraPDF's toolbar (src/shared/ToolbarCommon.cpp, gToolbarButtons) in the
/// same order, minus Read Aloud and Edit PDF, plus Find Previous/Next arrows
/// after the search field. Icons are SF Symbols.
@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSComboBoxDelegate {
    private weak var windowController: MainWindowController?
    private let pageField = NSTextField()
    private let pageTotal = NSTextField(labelWithString: "")
    private let zoomBox = NSComboBox()
    private var searchItem: NSSearchToolbarItem?

    init(windowController: MainWindowController) {
        self.windowController = windowController
        super.init()
        configureControls()
    }

    private struct Button {
        let label: String
        let symbol: String
        let action: Selector
        /// Handled by this controller instead of the responder chain.
        var local = false
    }

    private static let buttons: [NSToolbarItem.Identifier: Button] = [
        .open: Button(label: "Open", symbol: "folder", action: #selector(AppDelegate.openDocument(_:))),
        .print: Button(label: "Print", symbol: "printer", action: #selector(MainWindowController.printDocument(_:))),
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
        .findPrevious: Button(
            label: "Find Previous", symbol: "chevron.left", action: #selector(findPreviousClicked(_:)), local: true),
        .findNext: Button(
            label: "Find Next", symbol: "chevron.right", action: #selector(findNextClicked(_:)), local: true),
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .open, .print, .space, .pageNumber, .previousPage, .nextPage, .space, .back, .forward,
            .flexibleSpace, .fitWidthContinuous, .fitPageSingle, .rotateLeft, .rotateRight, .zoomOut, .zoom, .zoomIn,
            .space, .find, .findPrevious, .findNext,
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
            if button.local { item.target = self }
            item.isBordered = true
            return item
        }
        switch identifier {
        case .pageNumber:
            return viewItem(identifier, label: "Page", view: pageStack())
        case .zoom:
            return viewItem(identifier, label: "Zoom", view: zoomBox)
        case .find:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.label = "Find"
            item.paletteLabel = "Find"
            item.preferredWidthForSearchField = 200
            configure(item.searchField)
            searchItem = item
            return item
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
        zoomBox.delegate = self
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
        let zoomText =
            UserInput.fitNames.first { $0.zoom == canvas.zoom }?.name
            ?? UserInput.format(percent: canvas.layout.zoomPercent)
        if zoomBox.currentEditor() == nil {
            zoomBox.stringValue = zoomText
        }
        // Otherwise choosing the item picked last time wouldn't count as a selection change.
        let selected = zoomBox.indexOfSelectedItem
        if selected >= 0, zoomBox.objectValueOfSelectedItem as? String != zoomText {
            zoomBox.deselectItem(at: selected)
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        windowController?.canvas != nil
    }

    // MARK: - Search field

    /// Return finds the next match, ⇧Return the previous one; the field keeps
    /// focus so Return can be pressed repeatedly, as in SumatraPDF's find box.
    private func configure(_ field: NSSearchField) {
        field.placeholderString = "Find"
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.target = self
        field.action = #selector(searchEntered(_:))
        let menu = NSMenu(title: "Find Options")
        menu.addItem(withTitle: "Match Case", action: #selector(DocumentView.toggleMatchCase(_:)), keyEquivalent: "")
        field.searchMenuTemplate = menu
    }

    @objc private func searchEntered(_ sender: NSSearchField) {
        guard let canvas = windowController?.canvas else { return }
        let backward = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if sender.stringValue.isEmpty {
            canvas.clearTextState()
        } else {
            canvas.find(sender.stringValue, forward: !backward)
        }
    }

    @objc private func findPreviousClicked(_ sender: Any?) { findFromToolbar(forward: false, sender: sender) }
    @objc private func findNextClicked(_ sender: Any?) { findFromToolbar(forward: true, sender: sender) }

    /// The arrows search for the field's text, so typing and clicking is
    /// enough; with an empty field they act like ⇧⌘G / ⌘G.
    private func findFromToolbar(forward: Bool, sender: Any?) {
        guard let canvas = windowController?.canvas else { return }
        let text = searchItem?.searchField.stringValue ?? ""
        if !text.isEmpty {
            canvas.find(text, forward: forward)
        } else if forward {
            canvas.findNext(sender)
        } else {
            canvas.findPrevious(sender)
        }
    }

    func focusSearch() -> Bool {
        guard let item = searchItem, item.searchField.window != nil else { return false }
        item.beginSearchInteraction()
        return true
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

    /// A choice in the drop-down list. The box still shows the old text while
    /// the selection changes, so the value comes from the chosen item.
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let canvas = windowController?.canvas, let text = zoomBox.objectValueOfSelectedItem as? String,
            let zoom = UserInput.zoom(text)
        else { return }
        canvas.setZoom(zoom)
    }

    // MARK: - Control channel

    /// Clicks the toolbar item `identifier` (see `ControlRequest.Command.toolbar`);
    /// false if it isn't on the toolbar or is disabled.
    func use(_ identifier: NSToolbarItem.Identifier, text: String?) -> Bool {
        guard let window = windowController?.window, let toolbar = window.toolbar,
            let item = toolbar.items.first(where: { $0.itemIdentifier == identifier })
        else { return false }
        switch identifier {
        case .zoom:
            guard let text, zoomBox.isEnabled else { return false }
            let index = zoomBox.indexOfItem(withObjectValue: text)
            guard index != NSNotFound else { return false }
            zoomBox.selectItem(at: index)
            return true
        case .find:
            guard let text, let field = searchItem?.searchField else { return false }
            field.stringValue = text
            return true
        default:
            toolbar.validateVisibleItems()
            guard item.isEnabled, let action = item.action else { return false }
            if let target = item.target { return NSApp.sendAction(action, to: target, from: item) }
            return (window.firstResponder ?? window).sendThroughChain(action, from: item)
        }
    }
}
