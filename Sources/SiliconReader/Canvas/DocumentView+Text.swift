import AppKit
import ReaderCore

/// Text interaction on the canvas: selection, copy, links and find.
extension DocumentView {
    /// SumatraPDF's SelectionColor (#ffff00) at its default opacity, multiplied so text stays crisp.
    static let selectionColor = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 0.5)
    /// Every match on screen; the current one uses the selection color.
    static let matchColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 0.35)
    /// Mouse travel (points) before a press on a link counts as a drag.
    private static let dragThreshold: CGFloat = 3

    // MARK: - Mouse

    func beginMouseInteraction(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = viewport.origin
        guard let hit = pageHit(at: point) else {
            selection = nil
            drag = .panning(start: event.locationInWindow, origin: origin)
            needsDisplay = true
            return
        }
        let text = textStore.text(hit.page)

        switch event.clickCount {
        case 2, 3:
            guard let index = text.glyphIndex(at: hit.point) ?? text.caretIndex(near: hit.point),
                index < text.scalars.count
            else { return }
            let range = event.clickCount == 2 ? text.wordRange(at: index) : text.lineRange(at: index)
            select(page: hit.page, range: range)
            drag = .none
            return
        default:
            break
        }

        if let link = links(onPage: hit.page).first(where: { $0.rect.contains(hit.point) }) {
            drag = .link(link, start: event.locationInWindow)
        } else if text.glyphIndex(at: hit.point) != nil, let caret = text.caretIndex(near: hit.point) {
            let position = TextPosition(page: hit.page, index: caret)
            selection = TextSelection(anchor: position, focus: position)
            drag = .selecting
        } else {
            // SumatraPDF pans when a drag starts away from text.
            selection = nil
            drag = .panning(start: event.locationInWindow, origin: origin)
        }
        needsDisplay = true
    }

    func continueMouseInteraction(_ event: NSEvent) {
        switch drag {
        case .selecting:
            let point = convert(event.locationInWindow, from: nil)
            guard var current = selection, let page = nearestPage(to: point), let geo = geometry(page) else { return }
            let text = textStore.text(page)
            let index = text.caretIndex(near: geo.pagePoint(fromCanvas: point)) ?? 0
            current.focus = TextPosition(page: page, index: index)
            selection = current
            needsDisplay = true
            autoscroll(with: event)
        case .panning(let start, let origin):
            let location = event.locationInWindow
            // Content follows the hand: dragging down reveals what is above.
            scroll(to: CGPoint(x: origin.x - (location.x - start.x), y: origin.y + (location.y - start.y)))
            NSCursor.closedHand.set()
        case .link(_, let start):
            let location = event.locationInWindow
            if hypot(location.x - start.x, location.y - start.y) > Self.dragThreshold {
                drag = .panning(start: start, origin: viewport.origin)
                continueMouseInteraction(event)
            }
        case .none:
            break
        }
    }

    func endMouseInteraction(_ event: NSEvent) {
        switch drag {
        case .link(let link, _):
            go(to: link.destination)
        case .selecting:
            if selection?.isEmpty == true { selection = nil }
            needsDisplay = true
        case .panning, .none:
            break
        }
        drag = .none
        let point = convert(event.locationInWindow, from: nil)
        if let hit = pageHit(at: point) { updateCursor(page: hit.page, point: hit.point) }
    }

    /// Pointing hand over links, I-beam over text (pages whose text is already known).
    func updateCursor(page: Int, point: CGPoint) {
        if links(onPage: page).contains(where: { $0.rect.contains(point) }) {
            NSCursor.pointingHand.set()
        } else if textStore.cached(page)?.glyphIndex(at: point) != nil {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func links(onPage page: Int) -> [PageLink] {
        if let cached = linkCache[page] { return cached }
        let links = (try? engine.links(onPage: page)) ?? []
        linkCache[page] = links
        return links
    }

    private func select(page: Int, range: Range<Int>) {
        selection = TextSelection(
            anchor: TextPosition(page: page, index: range.lowerBound),
            focus: TextPosition(page: page, index: range.upperBound))
        needsDisplay = true
    }

    // MARK: - Copy and select

    var selectedText: String {
        guard let selection else { return "" }
        return selection.pageRanges { textStore.text($0).scalars.count }
            .map { textStore.text($0.page).string(in: $0.range) }
            .joined(separator: "\n")
    }

    @objc func copy(_ sender: Any?) {
        let text = selectedText
        guard !text.isEmpty else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc override func selectAll(_ sender: Any?) {
        let last = pageCount - 1
        selection = TextSelection(
            anchor: TextPosition(page: 0, index: 0),
            focus: TextPosition(page: last, index: textStore.text(last).scalars.count))
        needsDisplay = true
    }

    /// SumatraPDF's Ctrl+4: zoom so the selection fills the window.
    @objc func zoomToSelection(_ sender: Any?) {
        guard let bounds = selectionBounds(), bounds.width > 0, bounds.height > 0 else { return NSSound.beep() }
        let fit = min(viewport.width / bounds.width, viewport.height / bounds.height) * 0.9
        setZoom(.percent(layout.zoomPercent * fit))
        if let after = selectionBounds() { center(on: after) }
    }

    /// Union of the selection's boxes on pages that are laid out, in canvas space.
    private func selectionBounds() -> CGRect? {
        guard let selection, !selection.isEmpty else { return nil }
        var bounds = CGRect.null
        for page in selection.start.page...selection.end.page {
            guard let geo = geometry(page), let text = textStore.cached(page),
                let range = selection.range(onPage: page, length: text.scalars.count)
            else { continue }
            for rect in text.rects(for: range) { bounds = bounds.union(geo.canvasRect(fromPage: rect)) }
        }
        return bounds.isNull ? nil : bounds
    }

    private func center(on rect: CGRect) {
        scroll(to: CGPoint(x: rect.midX - viewport.width / 2, y: rect.midY - viewport.height / 2))
    }

    func clearTextState() {
        searchTask?.cancel()
        searchTask = nil
        selection = nil
        searchQuery = nil
        currentMatch = nil
        onSearchStatus(nil)
        needsDisplay = true
    }

    // MARK: - Find

    /// Finds the next (or previous) occurrence of `query`, starting after the
    /// current match or at the current page; wraps around the document.
    func find(_ query: String, forward: Bool) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return clearTextState() }
        if query != searchQuery {
            searchQuery = query
            currentMatch = nil
        }
        let start: TextPosition
        if let match = currentMatch {
            start = TextPosition(page: match.page, index: forward ? match.range.lowerBound + 1 : match.range.lowerBound)
        } else {
            start = TextPosition(page: currentPage, index: forward ? 0 : Int.max)
        }

        searchTask?.cancel()
        let store = textStore
        let pageCount = pageCount
        let caseSensitive = matchCase
        onSearchStatus("Searching…")
        needsDisplay = true
        // Made here, not inside the detached task: Swift 6.0 treats whatever that
        // task's closures capture as task-isolated and won't send it to the main actor.
        let reportProgress: @Sendable (Int) -> Void = { [weak self] page in
            guard page % 10 == 0 else { return }
            Task { @MainActor in self?.onSearchStatus("Searching page \(page + 1) of \(pageCount)…") }
        }
        searchTask = Task { [weak self] in
            let match = await Task.detached(priority: .userInitiated) {
                DocumentSearch.next(
                    query, caseSensitive: caseSensitive, after: start, forward: forward, pageCount: pageCount,
                    text: store.text(_:), progress: reportProgress, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled, let self else { return }
            searchTask = nil
            searchFinished(match, query: query)
        }
    }

    private func searchFinished(_ match: TextMatch?, query: String) {
        guard let match else {
            currentMatch = nil
            onSearchStatus("No matches for “\(query)”")
            NSSound.beep()
            needsDisplay = true
            return
        }
        currentMatch = match
        select(page: match.page, range: match.range)
        onSearchStatus("Found on page \(match.page + 1)")
        reveal(match)
    }

    /// Brings a match into view, switching pages in non-continuous modes.
    private func reveal(_ match: TextMatch) {
        if layout.pageFrames.indices.contains(match.page), layout.pageFrames[match.page] == nil {
            goToPage(match.page)
        }
        guard let geo = geometry(match.page) else { return }
        let rect = match.rects.map { geo.canvasRect(fromPage: $0) }.reduce(CGRect.null) { $0.union($1) }
        guard !rect.isNull, !viewport.insetBy(dx: 0, dy: viewport.height * 0.1).contains(rect) else { return }
        // Keep the horizontal position unless the match is off to the side.
        let fitsHorizontally = viewport.minX <= rect.minX && rect.maxX <= viewport.maxX
        let x = fitsHorizontally ? viewport.minX : rect.midX - viewport.width / 2
        scroll(to: CGPoint(x: x, y: rect.midY - viewport.height / 3))
    }

    @objc func findNext(_ sender: Any?) { repeatFind(forward: true) }
    @objc func findPrevious(_ sender: Any?) { repeatFind(forward: false) }

    private func repeatFind(forward: Bool) {
        guard let query = searchQuery else {
            sendThroughChain(#selector(MainWindowController.showFind(_:)), from: self)
            return
        }
        find(query, forward: forward)
    }

    @objc func toggleMatchCase(_ sender: Any?) {
        matchCase.toggle()
        currentMatch = nil
        needsDisplay = true
    }

    // MARK: - Drawing

    /// Selection and search highlights for one page, multiplied over the page
    /// image so the text underneath stays black.
    func drawTextHighlights(page: Int, geometry geo: PageGeometry, in ctx: CGContext) {
        guard selection != nil || searchQuery != nil else { return }
        let text = textStore.text(page)
        guard !text.isEmpty else { return }

        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        if let query = searchQuery {
            ctx.setFillColor(Self.matchColor.cgColor)
            for match in TextSearch.matches(of: query, in: text, page: page, caseSensitive: matchCase) {
                match.rects.forEach { ctx.fill(geo.canvasRect(fromPage: $0)) }
            }
        }
        if let selection, let range = selection.range(onPage: page, length: text.scalars.count) {
            ctx.setFillColor(Self.selectionColor.cgColor)
            text.rects(for: range).forEach { ctx.fill(geo.canvasRect(fromPage: $0)) }
        }
        ctx.restoreGState()
    }
}
