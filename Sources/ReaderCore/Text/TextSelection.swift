import CoreGraphics

/// A caret position in the document: between scalars `index - 1` and `index`
/// of a page's text (0...count).
public struct TextPosition: Hashable, Comparable, Sendable {
    public var page: Int
    public var index: Int

    public init(page: Int, index: Int) {
        self.page = page
        self.index = index
    }

    public static func < (a: TextPosition, b: TextPosition) -> Bool {
        (a.page, a.index) < (b.page, b.index)
    }
}

/// A text selection from where the drag started to where it is now; may span pages.
public struct TextSelection: Hashable, Sendable {
    public var anchor: TextPosition
    public var focus: TextPosition

    public init(anchor: TextPosition, focus: TextPosition) {
        self.anchor = anchor
        self.focus = focus
    }

    public var start: TextPosition { min(anchor, focus) }
    public var end: TextPosition { max(anchor, focus) }
    public var isEmpty: Bool { anchor == focus }

    /// The selected range on one page, nil if the page is outside the
    /// selection. Only that page's length is needed, so drawing a page never
    /// forces text extraction for the rest of a long selection.
    public func range(onPage page: Int, length: Int) -> Range<Int>? {
        let start = start
        let end = end
        guard start != end, (start.page...end.page).contains(page) else { return nil }
        let lower = page == start.page ? min(start.index, length) : 0
        let upper = page == end.page ? min(end.index, length) : length
        return lower < upper ? lower..<upper : nil
    }

    /// The selected scalar range on each page, in page order. `length` gives
    /// each page's text length (for pages fully inside the selection).
    public func pageRanges(length: (Int) -> Int) -> [(page: Int, range: Range<Int>)] {
        let start = start
        let end = end
        guard start != end else { return [] }
        return (start.page...end.page).compactMap { page in
            let lower = page == start.page ? start.index : 0
            let upper = page == end.page ? end.index : length(page)
            return lower < upper ? (page, lower..<upper) : nil
        }
    }
}

extension PageText {
    /// The caret position closest to `point` (page space): first the visual
    /// line nearest vertically, then the gap between glyphs nearest
    /// horizontally. Used for drag selection, so it always returns something
    /// for non-empty text, even for points far outside the text.
    public func caretIndex(near point: CGPoint) -> Int? {
        let glyphs = rects.indices.filter { !rects[$0].isNull }
        guard !glyphs.isEmpty else { return nil }

        func verticalDistance(_ i: Int) -> CGFloat {
            let r = rects[i]
            return point.y < r.minY ? r.minY - point.y : (point.y > r.maxY ? point.y - r.maxY : 0)
        }
        // Text on the same line shares a line id; pick the line of the closest glyph.
        guard let closest = glyphs.min(by: { verticalDistance($0) < verticalDistance($1) }) else { return nil }
        let line = lines[closest]
        let onLine = glyphs.filter { lines[$0] == line }

        if let i = onLine.first(where: { point.x < rects[$0].midX }) {
            return i
        }
        return (onLine.last ?? closest) + 1
    }

    /// Index of the glyph whose box contains `point`, if any.
    public func glyphIndex(at point: CGPoint) -> Int? {
        rects.indices.first { !rects[$0].isNull && rects[$0].contains(point) }
    }

    /// The word around `index` (letters, digits and connectors); empty for whitespace/punctuation.
    public func wordRange(at index: Int) -> Range<Int> {
        guard scalars.indices.contains(index) else { return index..<index }
        func isWord(_ i: Int) -> Bool {
            let p = scalars[i].properties
            return p.isAlphabetic || p.numericType != nil || scalars[i] == "_"
        }
        guard isWord(index) else { return index..<(index + 1) }
        var lower = index
        var upper = index + 1
        while lower > 0 && isWord(lower - 1) { lower -= 1 }
        while upper < scalars.count && isWord(upper) { upper += 1 }
        return lower..<upper
    }

    /// All glyphs on the visual line of `index`, without the synthesized line break.
    public func lineRange(at index: Int) -> Range<Int> {
        guard lines.indices.contains(index) else { return index..<index }
        let line = lines[index]
        let onLine = lines.indices.filter { lines[$0] == line && !rects[$0].isNull }
        guard let first = onLine.first, let last = onLine.last else { return index..<index }
        return first..<(last + 1)
    }
}
