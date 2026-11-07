import AppKit
import ReaderCore

/// Identifies an annotation until its page changes.
struct AnnotationReference: Equatable {
    var page: Int
    var index: Int
}

/// PDF annotations on the canvas: creating, picking, editing and deleting them.
/// Saving is the window's job (`MainWindowController.saveAnnotations`).
extension DocumentView {
    private static let strokeColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private static let strokeWidth: CGFloat = 2

    // MARK: - Reading

    func annotations(onPage page: Int) -> [PageAnnotation] {
        if let cached = annotationCache[page] { return cached }
        let annotations = engine.supportsAnnotations ? (try? engine.annotations(onPage: page)) ?? [] : []
        annotationCache[page] = annotations
        return annotations
    }

    /// The topmost annotation at a page point.
    func annotation(atPage page: Int, point: CGPoint) -> PageAnnotation? {
        annotations(onPage: page).last { $0.rect.contains(point) }
    }

    var selectedAnnotationDetails: PageAnnotation? {
        guard let selectedAnnotation else { return nil }
        return annotations(onPage: selectedAnnotation.page).first { $0.index == selectedAnnotation.index }
    }

    /// Note text under the pointer, shown as a tooltip.
    func showNoteTip(page: Int, point: CGPoint) {
        guard engine.supportsAnnotations else { return }
        let note = annotation(atPage: page, point: point)?.contents
        let tip = note?.isEmpty == false ? note : nil
        if toolTip != tip { toolTip = tip }
    }

    // MARK: - Commands

    @objc func annotateHighlight(_ sender: Any?) { markSelection(.highlight) }
    @objc func annotateUnderline(_ sender: Any?) { markSelection(.underline) }
    @objc func annotateStrikeOut(_ sender: Any?) { markSelection(.strikeOut) }

    /// One annotation per page of the selection, with a box per line; the
    /// selection goes away so the mark can be seen.
    private func markSelection(_ kind: AnnotationKind) {
        guard let selection, !selection.isEmpty else { return NSSound.beep() }
        for part in selection.pageRanges(length: { textStore.text($0).scalars.count }) {
            let rects = textStore.text(part.page).rects(for: part.range)
            guard !rects.isEmpty else { continue }
            edit(page: part.page) { try engine.addMarkup(kind, rects: rects, onPage: part.page) }
        }
        self.selection = nil
    }

    @objc func annotateNote(_ sender: Any?) {
        guard let place = notePlace ?? pageCenter, let text = Self.askNoteText(initial: ""), !text.isEmpty else {
            return
        }
        addNote(text, onPage: place.page, at: place.point)
    }

    /// The middle of the current page, for Add Note without a pointer over a page.
    private var pageCenter: (page: Int, point: CGPoint)? {
        guard let geo = geometry(currentPage) else { return nil }
        let frame = geo.frame.intersection(viewport)
        return (currentPage, geo.pagePoint(fromCanvas: CGPoint(x: frame.midX, y: frame.midY)))
    }

    func addNote(_ text: String, onPage page: Int, at point: CGPoint) {
        edit(page: page) { try engine.addNote(text, at: point, onPage: page) }
    }

    @objc func toggleDrawing(_ sender: Any?) {
        isDrawing.toggle()
        selectAnnotation(nil)
        onSearchStatus(isDrawing ? "Draw: drag on the page, Esc to stop" : nil)
        if isDrawing {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func finishStroke(onPage page: Int) {
        let stroke = currentStroke
        currentStroke = []
        needsDisplay = true
        // A click without movement leaves a dot; a line needs two points.
        addFreehand([stroke.count > 1 ? stroke : stroke + stroke], onPage: page)
    }

    func addFreehand(_ strokes: [[CGPoint]], onPage page: Int) {
        edit(page: page) { try engine.addFreehand(strokes: strokes, onPage: page) }
    }

    @objc func editAnnotation(_ sender: Any?) {
        guard let selectedAnnotation, let details = selectedAnnotationDetails,
            let text = Self.askNoteText(initial: details.contents)
        else { return }
        edit(page: selectedAnnotation.page) {
            try engine.setContents(text, ofAnnotation: details.index, onPage: selectedAnnotation.page)
        }
    }

    @objc func deleteAnnotation(_ sender: Any?) {
        guard let selectedAnnotation else { return NSSound.beep() }
        edit(page: selectedAnnotation.page) {
            try engine.removeAnnotation(selectedAnnotation.index, onPage: selectedAnnotation.page)
        }
        self.selectedAnnotation = nil
    }

    func selectAnnotation(_ reference: AnnotationReference?) {
        selectedAnnotation = reference
        onSearchStatus(selectedAnnotationDetails.flatMap { $0.contents.isEmpty ? nil : $0.contents })
        needsDisplay = true
    }

    /// Runs one change to `page` and brings everything showing it up to date.
    private func edit(page: Int, _ change: () throws -> Void) {
        do {
            try change()
        } catch {
            NSAlert(error: error).runModal()
        }
        annotationCache[page] = nil
        renderer.invalidate(page: page)
        needsDisplay = true
        onStateChange?()
    }

    private static func askNoteText(initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Note"
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        text.string = initial
        text.isRichText = false
        text.font = .systemFont(ofSize: 13)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = text
        return alert.runModal() == .alertFirstButtonReturn ? text.string : nil
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isPresenting, let hit = pageHit(at: convert(event.locationInWindow, from: nil)) else { return nil }
        notePlace = hit
        let picked = annotation(atPage: hit.page, point: hit.point)
        selectAnnotation(picked.map { AnnotationReference(page: hit.page, index: $0.index) })

        let menu = NSMenu()
        if !(selection?.isEmpty ?? true) {
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            if engine.supportsAnnotations {
                menu.addItem(.separator())
                menu.addItem(withTitle: "Highlight", action: #selector(annotateHighlight(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Underline", action: #selector(annotateUnderline(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Strike Out", action: #selector(annotateStrikeOut(_:)), keyEquivalent: "")
            }
        }
        if engine.supportsAnnotations {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(withTitle: "Add Note Here…", action: #selector(annotateNote(_:)), keyEquivalent: "")
        }
        if let picked {
            menu.addItem(.separator())
            if picked.kind != .other {
                menu.addItem(withTitle: "Edit Note…", action: #selector(editAnnotation(_:)), keyEquivalent: "")
            }
            menu.addItem(withTitle: "Delete Annotation", action: #selector(deleteAnnotation(_:)), keyEquivalent: "")
        }
        return menu.items.isEmpty ? nil : menu
    }

    // MARK: - Drawing

    /// The outline of the picked annotation and the stroke in progress.
    func drawAnnotationOverlay(page: Int, geometry geo: PageGeometry, in ctx: CGContext) {
        if selectedAnnotation?.page == page, let details = selectedAnnotationDetails {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(geo.canvasRect(fromPage: details.rect).insetBy(dx: -2, dy: -2))
            ctx.restoreGState()
        }
        if case .drawing(page) = drag, currentStroke.count > 1 {
            ctx.saveGState()
            ctx.concatenate(geo.transform)
            ctx.setStrokeColor(Self.strokeColor.cgColor)
            ctx.setLineWidth(Self.strokeWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addLines(between: currentStroke)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
