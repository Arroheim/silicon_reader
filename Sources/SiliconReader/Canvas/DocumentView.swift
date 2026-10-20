import AppKit
import ReaderCore

/// The document canvas: lays pages out like SumatraPDF's DisplayModel, draws
/// them from background-rendered tiles and handles navigation and zoom.
///
/// Lives as the document view of a `CanvasScrollView`; its frame is the whole
/// canvas and scrolling is done by the clip view.
@MainActor
final class DocumentView: NSView {
    /// Theme background around pages (SumatraPDF Light: #f2f2f2, Dark: #000000).
    static let canvasColor = NSColor(name: "canvas") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            : NSColor(srgbRed: 0xf2 / 255.0, green: 0xf2 / 255.0, blue: 0xf2 / 255.0, alpha: 1)
    }

    /// Longest side of the low-resolution whole-page image drawn while tiles render.
    private static let previewPixels: CGFloat = 768
    private static let lineScroll: CGFloat = 40

    let engine: any DocumentEngine
    private let pageSizes: [CGSize]
    private var contentBoxes: [CGRect?]
    private let renderer: TileRenderer

    private(set) var mode = ViewMode()
    private(set) var zoom: Zoom = .fitPage
    private(set) var rotation = 0
    private(set) var currentPage = 0
    private(set) var layout: DocumentLayout
    private var isLiveMagnifying = false
    private var drewEverythingWanted = false
    private var history = NavigationHistory()

    /// Session-only, like SumatraPDF's CmdInvertColors.
    private(set) var invertsColors = false
    /// Presentation mode: black surroundings, clicks turn pages.
    private(set) var isPresenting = false
    /// Presentation "black/white screen" (Sumatra's . and w).
    private var blankScreen: NSColor?
    private var autoScrollTask: Task<Void, Never>?
    /// Points per second; negative scrolls up.
    private var autoScrollSpeed: CGFloat = 40

    // Text: see DocumentView+Text.swift.
    let textStore: TextStore
    var selection: TextSelection?
    var searchQuery: String?
    var matchCase = false
    var currentMatch: TextMatch?
    var searchTask: Task<Void, Never>?
    var linkCache: [Int: [PageLink]] = [:]
    var drag = DragState.none
    /// Search progress and results for the window ("Searching page 5 of 39…").
    var onSearchStatus: (String?) -> Void = { _ in }

    enum DragState {
        case none
        case selecting
        /// Hand-panning: where the mouse went down (window coords) and the scroll origin then.
        case panning(start: CGPoint, origin: CGPoint)
        /// Mouse went down on a link; follows it unless the mouse moves.
        case link(PageLink, start: CGPoint)
    }

    /// Called after the current page, zoom or layout mode changes.
    var onStateChange: (() -> Void)?
    /// Pointer position over a page (page index, point in page space), nil when off the pages.
    var onPointerMoved: ((Int, CGPoint)?) -> Void = { _ in }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    init(engine: any DocumentEngine) {
        self.engine = engine
        // A page that fails to report its size is laid out as US Letter so the rest stays usable.
        pageSizes = (0..<engine.pageCount).map { (try? engine.pageSize(at: $0)) ?? CGSize(width: 612, height: 792) }
        contentBoxes = Array(repeating: nil, count: engine.pageCount)
        renderer = TileRenderer(engine: engine, maxConcurrent: engine.supportsRegionRendering ? 2 : 3)
        textStore = TextStore(engine: engine)
        layout = .empty
        super.init(frame: .zero)
        renderer.onTileReady = { [weak self] key in self?.tileReady(key) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Geometry

    private var clipView: NSClipView? { enclosingScrollView?.contentView }
    var viewport: CGRect { clipView?.bounds ?? bounds }

    var pageCount: Int { pageSizes.count }

    /// True once every visible page is drawn at full resolution and nothing is rendering.
    var isSettled: Bool { drewEverythingWanted && renderer.isIdle && searchTask == nil }

    func geometry(_ page: Int) -> PageGeometry? {
        layout.geometry(forPage: page, pageSize: pageSizes[page])
    }

    private func params(viewport size: CGSize) -> LayoutParams {
        LayoutParams(
            pageSizes: pageSizes, contentBoxes: contentBoxes, mode: mode, zoom: zoom, rotation: rotation,
            viewport: size, currentPage: currentPage)
    }

    /// Fit zoom percentages for the current viewport, used by zoom stepping.
    private func fitPercent(_ fit: Zoom) -> CGFloat {
        var p = params(viewport: viewport.size)
        p.zoom = fit
        return LayoutEngine.layout(p).zoomPercent
    }

    // MARK: - Layout

    private enum Anchor {
        /// Keep the document point under this viewport point where it is.
        case viewportPoint(CGPoint)
        /// Put the top of a page at the top of the viewport.
        case pageTop(Int)
    }

    /// Re-runs layout for the current state and restores the view position.
    private func relayout(keeping anchor: Anchor) {
        let saved = capture(anchor)
        if zoom == .fitContent {
            measureContent(around: currentPage)
        }
        layout = LayoutEngine.layout(params(viewport: viewport.size))
        setFrameSize(layout.canvasSize)
        restore(saved)
        needsDisplay = true
        updateCurrentPage()
        onStateChange?()
    }

    func viewportDidResize() {
        relayout(keeping: .viewportPoint(.zero))
    }

    private enum SavedPosition {
        case point(page: Int, pagePoint: CGPoint, viewportPoint: CGPoint)
        case pageTop(Int)
    }

    private func capture(_ anchor: Anchor) -> SavedPosition? {
        switch anchor {
        case .pageTop(let page):
            return .pageTop(page)
        case .viewportPoint(let point):
            let canvasPoint = CGPoint(x: viewport.minX + point.x, y: viewport.minY + point.y)
            guard let page = nearestPage(to: canvasPoint), let geo = geometry(page) else { return nil }
            return .point(page: page, pagePoint: geo.pagePoint(fromCanvas: canvasPoint), viewportPoint: point)
        }
    }

    private func restore(_ saved: SavedPosition?) {
        switch saved {
        case .pageTop(let page):
            scrollToPageTop(page)
        case .point(let page, let pagePoint, let viewportPoint):
            guard let geo = geometry(page) else { return scrollToPageTop(page) }
            let canvasPoint = geo.canvasPoint(fromPage: pagePoint)
            scroll(to: CGPoint(x: canvasPoint.x - viewportPoint.x, y: canvasPoint.y - viewportPoint.y))
        case nil:
            break
        }
    }

    func nearestPage(to point: CGPoint) -> Int? {
        var best: (page: Int, distance: CGFloat)?
        for (page, frame) in layout.pageFrames.enumerated() {
            guard let frame else { continue }
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < (best?.distance ?? .infinity) { best = (page, distance) }
        }
        return best?.page
    }

    private func measureContent(around page: Int) {
        let rows = LayoutEngine.rows(pageCount: pageCount, arrangement: mode.arrangement)
        guard let row = rows.first(where: { $0.pages.contains(page) }) else { return }
        for p in row.pages where contentBoxes[p] == nil {
            contentBoxes[p] = engine.contentBox(at: p)
        }
    }

    // MARK: - Scrolling

    func scroll(to origin: CGPoint) {
        guard let clipView, let scrollView = enclosingScrollView else { return }
        let maxX = max(0, layout.canvasSize.width - viewport.width)
        let maxY = max(0, layout.canvasSize.height - viewport.height)
        let clamped = CGPoint(x: min(max(origin.x, 0), maxX), y: min(max(origin.y, 0), maxY))
        clipView.scroll(to: clamped)
        scrollView.reflectScrolledClipView(clipView)
    }

    func scroll(by delta: CGPoint) {
        scroll(to: CGPoint(x: viewport.minX + delta.x, y: viewport.minY + delta.y))
    }

    private func scrollToPageTop(_ page: Int) {
        guard page < layout.pageFrames.count, let frame = layout.pageFrames[page] else { return }
        let margin = LayoutParams.defaultMargin
        var x = viewport.minX
        if frame.width <= viewport.width {
            x = 0
        } else if frame.minX > viewport.maxX || frame.maxX < viewport.minX {
            x = frame.minX - margin.left
        }
        scroll(to: CGPoint(x: x, y: frame.minY - margin.top))
    }

    /// Scrolls horizontally so the current page's content starts at the left margin (fit content).
    private func alignContentHorizontally() {
        guard let geo = geometry(currentPage), let box = contentBoxes[currentPage] else { return }
        let content = geo.canvasRect(fromPage: box)
        let margin = LayoutParams.defaultMargin
        scroll(to: CGPoint(x: content.minX - margin.left, y: viewport.minY))
    }

    func viewportDidScroll() {
        updateCurrentPage()
    }

    private func updateCurrentPage() {
        guard mode.continuous, let page = layout.mostVisiblePage(in: viewport) else { return }
        if page != currentPage {
            currentPage = page
            onStateChange?()
        }
    }

    private var canScrollDown: Bool { viewport.maxY < layout.canvasSize.height - 0.5 }
    private var canScrollUp: Bool { viewport.minY > 0.5 }
    private var canScrollHorizontally: Bool { layout.canvasSize.width > viewport.width + 0.5 }

    // MARK: - Navigation

    private var rows: [PageRow] { LayoutEngine.rows(pageCount: pageCount, arrangement: mode.arrangement) }

    func goToPage(_ page: Int) {
        let page = min(max(page, 0), pageCount - 1)
        if mode.continuous {
            currentPage = page
            scrollToPageTop(page)
            onStateChange?()
        } else {
            currentPage = rows.first { $0.pages.contains(page) }?.pages.lowerBound ?? page
            relayout(keeping: .pageTop(currentPage))
        }
    }

    /// Moves by whole rows, like SumatraPDF's next/previous page in facing modes.
    private func goToRow(offset: Int) {
        let rows = rows
        guard let index = rows.firstIndex(where: { $0.pages.contains(currentPage) }) else { return }
        let target = min(max(index + offset, 0), rows.count - 1)
        guard target != index || mode.continuous else { return }
        goToPage(rows[target].pages.lowerBound)
    }

    private func pageDown() {
        if canScrollDown {
            scroll(by: CGPoint(x: 0, y: viewport.height - Self.lineScroll))
        } else if !mode.continuous {
            goToRow(offset: 1)
        }
    }

    private func pageUp() {
        if canScrollUp {
            scroll(by: CGPoint(x: 0, y: -(viewport.height - Self.lineScroll)))
        } else if !mode.continuous && currentPage > 0 {
            goToRow(offset: -1)
            scroll(to: CGPoint(x: viewport.minX, y: layout.canvasSize.height))
        }
    }

    /// Wheel/trackpad scrolling past the end of a non-continuous page flips it.
    /// Returns true if the event turned the page.
    func flipPageForScroll(deltaY: CGFloat) -> Bool {
        guard !mode.continuous else { return false }
        if deltaY < 0 && !canScrollDown {
            let before = currentPage
            goToRow(offset: 1)
            return before != currentPage
        }
        if deltaY > 0 && !canScrollUp && currentPage > 0 {
            goToRow(offset: -1)
            scroll(to: CGPoint(x: viewport.minX, y: layout.canvasSize.height))
            return true
        }
        return false
    }

    // MARK: - Jumps and history

    /// The document point at the top-left of the viewport.
    var position: DocumentPosition {
        let corner = CGPoint(x: viewport.minX, y: viewport.minY)
        guard let page = nearestPage(to: corner), let geo = geometry(page) else {
            return DocumentPosition(page: currentPage)
        }
        return DocumentPosition(page: page, point: geo.pagePoint(fromCanvas: corner))
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    /// Follows a link or outline target, remembering where we came from.
    func go(to destination: Destination) {
        switch destination {
        case .uri(let uri):
            if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
        case .page(let page, let point):
            guard (0..<pageCount).contains(page) else { return }
            history.recordJump(from: position)
            show(DocumentPosition(page: page, point: point ?? .zero), alignToPageTop: point == nil)
        }
    }

    /// A jump to a page (page box, first/last page) that Back can undo.
    func jump(toPage page: Int) {
        history.recordJump(from: position)
        goToPage(page)
    }

    private func show(_ target: DocumentPosition, alignToPageTop: Bool = false) {
        if !mode.continuous || alignToPageTop {
            goToPage(target.page)
        }
        guard !alignToPageTop, let geo = geometry(target.page) else { return }
        let point = geo.canvasPoint(fromPage: target.point)
        scroll(to: CGPoint(x: canScrollHorizontally ? point.x : viewport.minX, y: point.y))
        updateCurrentPage()
        onStateChange?()
    }

    @objc func navigateBack(_ sender: Any?) {
        if let target = history.goBack(from: position) { show(target) }
    }

    @objc func navigateForward(_ sender: Any?) {
        if let target = history.goForward(from: position) { show(target) }
    }

    // MARK: - Zoom, mode, rotation

    func setZoom(_ newZoom: Zoom, at viewportPoint: CGPoint? = nil) {
        var newZoom = newZoom
        if case .percent(let p) = newZoom { newZoom = .clamped(p) }
        zoom = newZoom
        switch newZoom {
        case .percent:
            let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
            relayout(keeping: .viewportPoint(viewportPoint ?? center))
        case .fitWidth:
            relayout(keeping: .viewportPoint(CGPoint(x: 0, y: 0)))
        case .fitContent:
            relayout(keeping: .viewportPoint(CGPoint(x: 0, y: 0)))
            alignContentHorizontally()
        case .fitPage, .fitHeight, .shrinkToFit:
            relayout(keeping: .pageTop(currentPage))
        }
    }

    func zoomStep(in zoomIn: Bool, at viewportPoint: CGPoint? = nil) {
        let next = Zoom.step(
            from: layout.zoomPercent, zoomIn: zoomIn, fitPage: fitPercent(.fitPage), fitWidth: fitPercent(.fitWidth))
        setZoom(next, at: viewportPoint)
    }

    func setArrangement(_ arrangement: PageArrangement) {
        guard mode.arrangement != arrangement else { return }
        mode.arrangement = arrangement
        relayout(keeping: .pageTop(currentPage))
    }

    func setContinuous(_ continuous: Bool) {
        guard mode.continuous != continuous else { return }
        let page = currentPage
        mode.continuous = continuous
        if !continuous {
            currentPage = rows.first { $0.pages.contains(page) }?.pages.lowerBound ?? page
        }
        relayout(keeping: .pageTop(page))
    }

    func rotate(by degrees: Int) {
        rotation = ((rotation + degrees) % 360 + 360) % 360
        relayout(keeping: .pageTop(currentPage))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let blankScreen {
            blankScreen.setFill()
            dirtyRect.fill()
            drewEverythingWanted = true
            return
        }
        (isPresenting ? NSColor.black : Self.canvasColor).setFill()
        dirtyRect.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let deviceScale = window?.backingScaleFactor ?? 2
        let visible = viewport
        // Prefetch previews one screen above and below.
        let nearby = visible.insetBy(dx: 0, dy: -visible.height)
        var previews: [TileKey] = []
        var tiles: [(key: TileKey, distance: CGFloat)] = []
        var missing = false

        for (page, frame) in layout.pageFrames.enumerated() {
            guard let frame, frame.intersects(nearby), let geo = geometry(page) else { continue }
            let pageSize = pageSizes[page]
            let previewKey = TileKey(page: page, scale: Self.previewPixels / max(pageSize.width, pageSize.height, 1))
            previews.append(previewKey)
            guard frame.intersects(visible) else { continue }

            let renderScale = geo.scale * deviceScale
            var pageTiles: [TileKey] = []
            if engine.supportsRegionRendering {
                let visiblePart = geo.pageRect(fromCanvas: frame.intersection(visible))
                    .intersection(CGRect(origin: .zero, size: pageSize))
                guard !visiblePart.isNull, !visiblePart.isEmpty else { continue }
                let side = TileKey.size / renderScale
                func span(_ low: CGFloat, _ high: CGFloat) -> ClosedRange<Int> {
                    let first = Int(low / side)
                    return first...max(first, Int((high - 0.001) / side))
                }
                for row in span(visiblePart.minY, visiblePart.maxY) {
                    for column in span(visiblePart.minX, visiblePart.maxX) {
                        pageTiles.append(TileKey(page: page, scale: renderScale, column: column, row: row))
                    }
                }
            } else {
                pageTiles.append(TileKey(page: page, scale: renderScale))
            }

            if !isLiveMagnifying {
                let center = CGPoint(x: visible.midX, y: visible.midY)
                for key in pageTiles {
                    let rect = geo.canvasRect(fromPage: tileRect(key, pageSize: pageSize))
                    tiles.append((key, hypot(rect.midX - center.x, rect.midY - center.y)))
                }
            }

            let ready = pageTiles.map { ($0, renderer.image(for: $0)) }
            let complete = !ready.contains { $0.1 == nil }
            missing = missing || !complete

            guard frame.intersects(dirtyRect) else { continue }
            NSColor.white.setFill()
            frame.fill()
            ctx.saveGState()
            ctx.clip(to: frame)
            if !complete {
                if let fallback = renderer.image(for: previewKey) ?? renderer.anyWholePageImage(for: page) {
                    drawPageImage(fallback, pageRect: CGRect(origin: .zero, size: pageSize), geometry: geo, in: ctx)
                }
            }
            for case (let key, let image?) in ready {
                drawPageImage(image, pageRect: tileRect(key, pageSize: pageSize), geometry: geo, in: ctx)
            }
            drawTextHighlights(page: page, geometry: geo, in: ctx)
            if invertsColors {
                // white - color: black text on white becomes white on black
                ctx.setBlendMode(.difference)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(frame)
            }
            ctx.restoreGState()
        }

        drewEverythingWanted = !missing && !isLiveMagnifying
        renderer.request(previews + tiles.sorted { $0.distance < $1.distance }.map(\.key))
    }

    private func tileRect(_ key: TileKey, pageSize: CGSize) -> CGRect {
        let page = CGRect(origin: .zero, size: pageSize)
        return key.region.map { $0.intersection(page) } ?? page
    }

    /// Draws an image covering `pageRect` (page space) through the page's transform.
    private func drawPageImage(_ image: CGImage, pageRect: CGRect, geometry geo: PageGeometry, in ctx: CGContext) {
        ctx.saveGState()
        ctx.concatenate(geo.transform)
        // The canvas is flipped (y down); CGContext.draw expects y up for images.
        ctx.translateBy(x: pageRect.minX, y: pageRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: pageRect.size))
        ctx.restoreGState()
    }

    private func tileReady(_ key: TileKey) {
        guard key.page < layout.pageFrames.count, let frame = layout.pageFrames[key.page] else { return }
        setNeedsDisplay(frame)
    }

    // MARK: - Input

    /// Single keys and Shift combinations come from `CommandTable` and are sent
    /// down the responder chain; ⌘/⌃ shortcuts are handled by the menu bar.
    override func keyDown(with event: NSEvent) {
        if event.specialKey == nil, event.charactersIgnoringModifiers == "\u{1b}" {
            return cancelOperation(nil)
        }
        if autoScrollTask != nil, adjustAutoScroll(event) { return }
        guard let shortcut = Self.shortcut(for: event), !shortcut.isMenuShortcut,
            let command = CommandTable.command(for: shortcut),
            NSApp.sendAction(Selector("\(command.action):"), to: nil, from: self)
        else {
            return super.keyDown(with: event)
        }
    }

    static func shortcut(for event: NSEvent) -> Shortcut? {
        var modifiers: KeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }

        let key: Key? =
            switch event.specialKey {
            case .upArrow?: .up
            case .downArrow?: .down
            case .leftArrow?: .left
            case .rightArrow?: .right
            case .pageUp?: .pageUp
            case .pageDown?: .pageDown
            case .home?: .home
            case .end?: .end
            case .f3?: .function(3)
            case .f5?: .function(5)
            case .f6?: .function(6)
            case .f11?: .function(11)
            case .f12?: .function(12)
            default: nil
            }
        if let key { return Shortcut(key, modifiers) }
        return event.charactersIgnoringModifiers.flatMap { Shortcut.fromEvent(characters: $0, modifiers: modifiers) }
    }

    /// Esc clears selection and search, then leaves auto-scroll, presentation
    /// or full screen, in that order.
    override func cancelOperation(_ sender: Any?) {
        if selection != nil || searchQuery != nil {
            clearTextState()
        } else if autoScrollTask != nil {
            stopAutoScroll()
        } else if isPresenting {
            NSApp.sendAction(#selector(MainWindowController.togglePresentation(_:)), to: nil, from: self)
        } else if window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isPresenting else { return goToRow(offset: 1) }
        window?.makeFirstResponder(self)
        beginMouseInteraction(event)
    }

    override func mouseDragged(with event: NSEvent) {
        continueMouseInteraction(event)
    }

    override func mouseUp(with event: NSEvent) {
        endMouseInteraction(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isPresenting else { return super.rightMouseDown(with: event) }
        goToRow(offset: -1)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = pageHit(at: point) else {
            NSCursor.arrow.set()
            return onPointerMoved(nil)
        }
        updateCursor(page: hit.page, point: hit.point)
        onPointerMoved(hit)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        onPointerMoved(nil)
    }

    /// The page under a canvas point and the point in that page's space.
    func pageHit(at point: CGPoint) -> (page: Int, point: CGPoint)? {
        guard let page = layout.pageFrames.firstIndex(where: { $0?.contains(point) == true }),
            let geo = geometry(page)
        else { return nil }
        return (page, geo.pagePoint(fromCanvas: point))
    }

    /// Left/right scroll when the canvas is wider than the window, otherwise
    /// they turn pages (SumatraPDF behaves the same in single page mode).
    private func horizontal(_ direction: CGFloat) {
        if canScrollHorizontally {
            scroll(by: CGPoint(x: direction * Self.lineScroll, y: 0))
        } else {
            goToRow(offset: Int(direction))
        }
    }

    // MARK: - Scrolling commands

    // NSResponder's standard actions, so system key bindings reach them too.
    override func scrollLineDown(_ sender: Any?) { scroll(by: CGPoint(x: 0, y: Self.lineScroll)) }
    override func scrollLineUp(_ sender: Any?) { scroll(by: CGPoint(x: 0, y: -Self.lineScroll)) }
    @objc func scrollLineLeft(_ sender: Any?) { horizontal(-1) }
    @objc func scrollLineRight(_ sender: Any?) { horizontal(1) }
    @objc func scrollHalfPageDown(_ sender: Any?) { scroll(by: CGPoint(x: 0, y: viewport.height / 2)) }
    @objc func scrollHalfPageUp(_ sender: Any?) { scroll(by: CGPoint(x: 0, y: -viewport.height / 2)) }
    @objc func scrollScreenLeft(_ sender: Any?) { scroll(by: CGPoint(x: -viewport.width, y: 0)) }
    @objc func scrollScreenRight(_ sender: Any?) { scroll(by: CGPoint(x: viewport.width, y: 0)) }
    @objc func scrollScreenDown(_ sender: Any?) { pageDown() }
    @objc func scrollScreenUp(_ sender: Any?) { pageUp() }

    // MARK: - Auto scroll

    @objc func toggleAutoScroll(_ sender: Any?) {
        if autoScrollTask != nil {
            stopAutoScroll()
            return
        }
        autoScrollTask = Task { [weak self] in
            let frame: Duration = .milliseconds(16)
            while !Task.isCancelled, let self {
                let delta = autoScrollSpeed * 0.016
                let before = viewport.minY
                scroll(by: CGPoint(x: 0, y: delta))
                if viewport.minY == before {
                    // Reached an end; in non-continuous mode move on to the next row.
                    if mode.continuous || !flipPageForScroll(deltaY: -delta) { break }
                }
                try? await Task.sleep(for: frame)
            }
            self?.autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    /// While auto-scrolling, ↑/↓ (and k/j) change the speed instead of scrolling.
    private func adjustAutoScroll(_ event: NSEvent) -> Bool {
        let step: CGFloat
        switch Self.shortcut(for: event) {
        case Shortcut(.down)?, Shortcut(.character("j"))?: step = 20
        case Shortcut(.up)?, Shortcut(.character("k"))?: step = -20
        default: return false
        }
        autoScrollSpeed += step
        return true
    }

    // MARK: - View effects

    @objc func invertColors(_ sender: Any?) {
        invertsColors.toggle()
        needsDisplay = true
    }

    /// Presentation look: black around a single fitted page, no scrollers.
    func setPresenting(_ presenting: Bool) {
        isPresenting = presenting
        blankScreen = nil
        if let scroll = enclosingScrollView {
            scroll.hasVerticalScroller = !presenting
            scroll.hasHorizontalScroller = !presenting
            scroll.backgroundColor = presenting ? .black : Self.canvasColor
        }
        needsDisplay = true
    }

    @objc func presentationBlackScreen(_ sender: Any?) { toggleBlank(.black) }
    @objc func presentationWhiteScreen(_ sender: Any?) { toggleBlank(.white) }

    private func toggleBlank(_ color: NSColor) {
        guard isPresenting else { return NSSound.beep() }
        blankScreen = blankScreen == color ? nil : color
        needsDisplay = true
    }

    // MARK: - View state

    var viewState: ViewState {
        ViewState(mode: mode, zoom: zoom, rotation: rotation, position: position)
    }

    /// Restores mode, zoom, rotation and position (reload, duplicate window).
    func apply(_ state: ViewState) {
        mode = state.mode
        zoom = state.zoom
        rotation = state.rotation
        let page = min(max(state.position.page, 0), pageCount - 1)
        currentPage = mode.continuous ? page : rows.first { $0.pages.contains(page) }?.pages.lowerBound ?? page
        relayout(keeping: .pageTop(page))
        show(DocumentPosition(page: page, point: state.position.point))
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let viewportPoint = CGPoint(x: point.x - viewport.minX, y: point.y - viewport.minY)
        switch event.phase {
        case .began:
            isLiveMagnifying = true
        case .ended, .cancelled:
            isLiveMagnifying = false
            needsDisplay = true
            return
        default:
            break
        }
        setZoom(.percent(layout.zoomPercent * (1 + event.magnification)), at: viewportPoint)
    }

    override func smartMagnify(with event: NSEvent) {
        setZoom(zoom == .fitWidth ? .fitPage : .fitWidth)
    }

    // MARK: - Menu commands

    @objc func viewSinglePage(_ sender: Any?) { setArrangement(.single) }
    @objc func viewFacing(_ sender: Any?) { setArrangement(.facing) }
    @objc func viewBook(_ sender: Any?) { setArrangement(.book) }
    @objc func toggleContinuous(_ sender: Any?) { setContinuous(!mode.continuous) }
    @objc func zoomFitPage(_ sender: Any?) { setZoom(.fitPage) }
    @objc func zoomFitWidth(_ sender: Any?) { setZoom(.fitWidth) }
    @objc func zoomFitContent(_ sender: Any?) { setZoom(.fitContent) }
    @objc func zoomActualSize(_ sender: Any?) { setZoom(.actualSize) }
    @objc func zoomIn(_ sender: Any?) { zoomStep(in: true) }
    @objc func zoomOut(_ sender: Any?) { zoomStep(in: false) }
    @objc func toggleZoom(_ sender: Any?) { setZoom(zoom.toggled) }
    @objc func rotateLeft(_ sender: Any?) { rotate(by: -90) }
    @objc func rotateRight(_ sender: Any?) { rotate(by: 90) }
    @objc func goToNextPage(_ sender: Any?) { goToRow(offset: 1) }
    @objc func goToPreviousPage(_ sender: Any?) { goToRow(offset: -1) }
    @objc func goToFirstPage(_ sender: Any?) { jump(toPage: 0) }
    @objc func goToLastPage(_ sender: Any?) { jump(toPage: pageCount - 1) }

    /// SumatraPDF's two layout toolbar buttons.
    @objc func fitWidthContinuous(_ sender: Any?) {
        setContinuous(true)
        setZoom(.fitWidth)
    }

    @objc func fitPageSingle(_ sender: Any?) {
        setArrangement(.single)
        setContinuous(false)
        setZoom(.fitPage)
    }
}

extension DocumentView: NSMenuItemValidation, NSToolbarItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let checked = isChecked(item.action) { item.state = checked ? .on : .off }
        return isEnabled(item.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled(item.action)
    }

    /// Check mark for mode/zoom commands; nil for plain commands.
    func isChecked(_ action: Selector?) -> Bool? {
        switch action {
        case #selector(viewSinglePage(_:)): mode.arrangement == .single
        case #selector(viewFacing(_:)): mode.arrangement == .facing
        case #selector(viewBook(_:)): mode.arrangement == .book
        case #selector(toggleContinuous(_:)): mode.continuous
        case #selector(zoomFitPage(_:)): zoom == .fitPage
        case #selector(zoomFitWidth(_:)): zoom == .fitWidth
        case #selector(zoomFitContent(_:)): zoom == .fitContent
        case #selector(zoomActualSize(_:)): zoom == .actualSize
        case #selector(fitWidthContinuous(_:)): zoom == .fitWidth && mode.continuous
        case #selector(fitPageSingle(_:)): zoom == .fitPage && !mode.continuous && mode.arrangement == .single
        case #selector(invertColors(_:)): invertsColors
        case #selector(toggleMatchCase(_:)): matchCase
        case #selector(toggleAutoScroll(_:)): autoScrollTask != nil
        default: nil
        }
    }

    func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(goToNextPage(_:)), #selector(goToLastPage(_:)): currentPage < pageCount - 1
        case #selector(goToPreviousPage(_:)), #selector(goToFirstPage(_:)): currentPage > 0
        case #selector(zoomIn(_:)): layout.zoomPercent < Zoom.maxPercent - 0.01
        case #selector(zoomOut(_:)): layout.zoomPercent > Zoom.minPercent + 0.01
        case #selector(navigateBack(_:)): canGoBack
        case #selector(navigateForward(_:)): canGoForward
        case #selector(copy(_:)), #selector(zoomToSelection(_:)): !(selection?.isEmpty ?? true)
        default: true
        }
    }
}
