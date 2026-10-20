import AppKit
import ReaderCore

/// Off-screen view that prints one document page per sheet. Pages are
/// rendered by the document engine at `dpi`, so PDF and DjVu (including
/// password-protected PDFs, already unlocked) print the same way.
@MainActor
final class PrintView: NSView {
    private let engine: any DocumentEngine
    private let dpi: CGFloat

    init(engine: any DocumentEngine, printableSize: CGSize, dpi: CGFloat = 300) {
        self.engine = engine
        self.dpi = dpi
        super.init(frame: CGRect(origin: .zero, size: printableSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: engine.pageCount)
        return true
    }

    /// Every sheet uses the whole view; `draw` picks the page from the operation.
    override func rectForPage(_ page: Int) -> NSRect {
        bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let operation = NSPrintOperation.current, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let page = operation.currentPage - 1
        guard (0..<engine.pageCount).contains(page), let pageSize = try? engine.pageSize(at: page) else { return }

        let placement = PrintLayout.place(pageSize: pageSize, in: bounds)
        let rect = placement.rect
        let fitted = placement.rotated ? CGSize(width: rect.height, height: rect.width) : rect.size
        let scale = fitted.width / pageSize.width * dpi / 72
        guard let image = try? engine.render(page: page, scale: scale) else { return }

        ctx.saveGState()
        ctx.translateBy(x: placement.rect.midX, y: placement.rect.midY)
        // In this flipped view a positive angle turns clockwise.
        if placement.rotated { ctx.rotate(by: .pi / 2) }
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(
            image, in: CGRect(x: -fitted.width / 2, y: -fitted.height / 2, width: fitted.width, height: fitted.height))
        ctx.restoreGState()
    }

    /// Runs the system print dialog as a sheet on `window`, or with `saveTo`
    /// prints straight into a PDF without any UI (debug hook `-printToPDF`).
    static func run(engine: any DocumentEngine, title: String, for window: NSWindow, saveTo: URL? = nil) {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        let margin: CGFloat = 18  // 1/4", within what most printers can reach
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let printable = CGSize(width: info.paperSize.width - 2 * margin, height: info.paperSize.height - 2 * margin)

        if let saveTo {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = saveTo
        }

        let operation = NSPrintOperation(view: PrintView(engine: engine, printableSize: printable), printInfo: info)
        operation.jobTitle = title
        if saveTo != nil {
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.run()
            return
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPageRange, .showsCopies, .showsPaperSize, .showsPreview])
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
