import AppKit
import ReaderCore

/// SumatraPDF's Document Properties: label/value pairs and Copy to Clipboard.
@MainActor
final class PropertiesWindowController: NSWindowController {
    private let rows: [DocumentProperties.Row]

    init(engine: any DocumentEngine) {
        let size = (try? engine.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        rows = DocumentProperties.rows(
            url: engine.url, fileSize: size, metadata: engine.metadata, pageCount: engine.pageCount,
            firstPageSize: try? engine.pageSize(at: 0))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        panel.title = "Document Properties"
        super.init(window: panel)
        panel.contentView = makeContent()
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        let grid = NSGridView(
            views: rows.map { row -> [NSView] in
                let label = NSTextField(labelWithString: row.label + ":")
                label.textColor = .secondaryLabelColor
                label.alignment = .right
                let value = NSTextField(wrappingLabelWithString: row.value)
                value.isSelectable = true
                value.preferredMaxLayoutWidth = 400
                return [label, value]
            })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        grid.columnSpacing = 10

        let copy = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyToClipboard(_:)))
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow(_:)))
        close.keyEquivalent = "\r"
        let buttons = NSStackView(views: [copy, close])

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    @objc private func copyToClipboard(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DocumentProperties.text(rows), forType: .string)
    }

    @objc private func closeWindow(_ sender: Any?) {
        close()
    }
}
