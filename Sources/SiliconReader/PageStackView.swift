import AppKit
import ReaderCore

/// Phase-0 canvas: pages stacked vertically, fit to width, rendered lazily in
/// the background. Replaced by the tiled canvas in phase 1.
@MainActor
final class PageStackView: NSView {
    static let canvasColor = NSColor(calibratedWhite: 0.6, alpha: 1)
    private static let margin: CGFloat = 8
    private static let spacing: CGFloat = 8

    private struct Rendered {
        let image: CGImage
        let scale: CGFloat
    }

    private let engine: any DocumentEngine
    private let pageSizes: [CGSize]
    private var pageFrames: [CGRect] = []
    private var zoom: CGFloat = 1
    private var rendered: [Int: Rendered] = [:]
    private var inFlight: [Int: CGFloat] = [:]

    override var isFlipped: Bool { true }

    private var wantedScale: CGFloat { zoom * (window?.backingScaleFactor ?? 2) }

    /// True once every visible page is drawn at the current resolution.
    var isSettled: Bool {
        let wanted = wantedScale
        let visible = pageFrames.indices.filter { pageFrames[$0].intersects(visibleRect) }
        return !visible.isEmpty && visible.allSatisfy { rendered[$0]?.scale == wanted }
    }

    init(engine: any DocumentEngine) {
        self.engine = engine
        // A page that fails to report its size is laid out as US Letter so the rest stays usable.
        pageSizes = (0..<engine.pageCount).map { (try? engine.pageSize(at: $0)) ?? CGSize(width: 612, height: 792) }
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func layoutPages(forWidth width: CGFloat) {
        let widest = pageSizes.map(\.width).max() ?? 1
        zoom = max(0.1, (width - 2 * Self.margin) / widest)

        var y = Self.margin
        pageFrames = pageSizes.map { size in
            let w = size.width * zoom
            let h = size.height * zoom
            defer { y += h + Self.spacing }
            return CGRect(x: ((width - w) / 2).rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
        }
        setFrameSize(NSSize(width: width, height: y - Self.spacing + Self.margin))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.canvasColor.setFill()
        dirtyRect.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let wanted = wantedScale
        let keep = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)

        for (index, frame) in pageFrames.enumerated() {
            guard frame.intersects(keep) else {
                rendered[index] = nil
                continue
            }
            guard frame.intersects(dirtyRect) else { continue }

            NSColor.white.setFill()
            frame.fill()
            if let page = rendered[index] {
                drawImage(page.image, in: frame, context: ctx)
            }
            if rendered[index]?.scale != wanted {
                requestRender(index, scale: wanted)
            }
        }
    }

    private func drawImage(_ image: CGImage, in frame: CGRect, context ctx: CGContext) {
        // The view is flipped; CGContext.draw expects a bottom-up image space.
        ctx.saveGState()
        ctx.translateBy(x: frame.minX, y: frame.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: frame.size))
        ctx.restoreGState()
    }

    private func requestRender(_ index: Int, scale: CGFloat) {
        guard inFlight[index] != scale else { return }
        inFlight[index] = scale
        let engine = engine
        Task.detached(priority: .userInitiated) {
            let image = try? engine.render(page: index, scale: scale)
            await self.didRender(index, image: image, scale: scale)
        }
    }

    private func didRender(_ index: Int, image: CGImage?, scale: CGFloat) {
        guard inFlight[index] == scale else { return }
        inFlight[index] = nil
        guard let image, index < pageFrames.count else { return }
        rendered[index] = Rendered(image: image, scale: scale)
        setNeedsDisplay(pageFrames[index])
    }
}
