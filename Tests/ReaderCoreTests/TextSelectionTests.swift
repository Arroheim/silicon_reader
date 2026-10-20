import CoreGraphics
import Testing

@testable import ReaderCore

// PageText.grid lays scalar i of row r at (i * 10, r * 10, 10, 10).

@Suite("Text selection")
struct TextSelectionTests {
    private let text = PageText.grid(["hello world", "second"])

    @Test(
        "puts the caret in the nearest gap between glyphs",
        arguments: [
            (CGPoint(x: 1, y: 5), 0),  // left half of "h"
            (CGPoint(x: 9, y: 5), 1),  // right half of "h"
            (CGPoint(x: 500, y: 5), 11),  // past the end of line 1
            (CGPoint(x: -50, y: 15), 12),  // before "second"
            (CGPoint(x: 12, y: -100), 1),  // far above: first line, left half of "e"
            (CGPoint(x: 999, y: 999), 18),  // far below and right: end of text
        ])
    func caret(point: CGPoint, expected: Int) {
        #expect(text.caretIndex(near: point) == expected)
    }

    @Test("has no caret in empty text")
    func emptyCaret() {
        #expect(PageText.empty.caretIndex(near: .zero) == nil)
    }

    @Test("finds the glyph under a point")
    func glyphHit() {
        #expect(text.glyphIndex(at: CGPoint(x: 65, y: 5)) == 6)  // "w"
        #expect(text.glyphIndex(at: CGPoint(x: 200, y: 5)) == nil)
    }

    @Test("expands to the word or line around an index", arguments: [(0, 0..<5), (8, 6..<11), (5, 5..<6)])
    func word(index: Int, expected: Range<Int>) {
        #expect(text.wordRange(at: index) == expected)
    }

    @Test("expands to the visual line")
    func line() {
        #expect(text.lineRange(at: 3) == 0..<11)
        #expect(text.lineRange(at: 14) == 12..<18)
    }

    @Test("splits a cross-page selection into per-page ranges, whichever way it was dragged")
    func pageRanges() {
        let lengths = [0: 100, 1: 50, 2: 80]
        let forward = TextSelection(anchor: TextPosition(page: 0, index: 90), focus: TextPosition(page: 2, index: 10))
        let backward = TextSelection(anchor: forward.focus, focus: forward.anchor)

        let ranges = forward.pageRanges { lengths[$0]! }

        #expect(ranges.map(\.page) == [0, 1, 2])
        #expect(ranges.map(\.range) == [90..<100, 0..<50, 0..<10])
        #expect(backward.pageRanges { lengths[$0]! }.map(\.range) == ranges.map(\.range))
        #expect(TextSelection(anchor: forward.anchor, focus: forward.anchor).pageRanges { lengths[$0]! }.isEmpty)
    }

    @Test("gives the range on a single page without other pages' lengths")
    func rangeOnPage() {
        let selection = TextSelection(anchor: TextPosition(page: 2, index: 10), focus: TextPosition(page: 0, index: 90))

        #expect(selection.range(onPage: 0, length: 100) == 90..<100)
        #expect(selection.range(onPage: 1, length: 50) == 0..<50)
        #expect(selection.range(onPage: 2, length: 80) == 0..<10)
        #expect(selection.range(onPage: 3, length: 80) == nil)
        #expect(selection.range(onPage: 0, length: 60) == nil, "start beyond a shorter page's text")
    }
}

@Suite("Document search")
struct DocumentSearchTests {
    // "cat" at index 0 and 8 on page 0, none on page 1, index 4 on page 2.
    private let pages = [
        PageText.grid(["cat dog cat"]),
        PageText.grid(["nothing here"]),
        PageText.grid(["the cat"]),
    ]

    private func next(from page: Int, _ index: Int, forward: Bool = true) -> TextPosition? {
        DocumentSearch.next(
            "cat", caseSensitive: false, after: TextPosition(page: page, index: index), forward: forward,
            pageCount: pages.count, text: { pages[$0] }
        ).map { TextPosition(page: $0.page, index: $0.range.lowerBound) }
    }

    @Test("walks forward through matches and pages")
    func forward() {
        #expect(next(from: 0, 0) == TextPosition(page: 0, index: 0))
        #expect(next(from: 0, 1) == TextPosition(page: 0, index: 8))
        #expect(next(from: 0, 9) == TextPosition(page: 2, index: 4))
    }

    @Test("wraps around the end of the document")
    func wrapsForward() {
        #expect(next(from: 2, 5) == TextPosition(page: 0, index: 0))
    }

    @Test("walks backward and wraps around the start")
    func backward() {
        #expect(next(from: 2, 4, forward: false) == TextPosition(page: 0, index: 8))
        #expect(next(from: 0, 8, forward: false) == TextPosition(page: 0, index: 0))
        #expect(next(from: 0, 0, forward: false) == TextPosition(page: 2, index: 4))
    }

    @Test("finds the only match again after a full lap")
    func singleMatch() {
        let only = [PageText.grid(["one cat"]), PageText.grid(["none"])]
        let match = DocumentSearch.next(
            "cat", caseSensitive: false, after: TextPosition(page: 0, index: 5), forward: true, pageCount: 2,
            text: { only[$0] })
        #expect(match?.range == 4..<7)
    }

    @Test("returns nil when nothing matches and reports every page")
    func noMatch() {
        var visited: [Int] = []
        let match = DocumentSearch.next(
            "zebra", caseSensitive: false, after: TextPosition(page: 1, index: 0), forward: true,
            pageCount: pages.count, text: { pages[$0] }, progress: { visited.append($0) })
        #expect(match == nil)
        #expect(Set(visited) == [0, 1, 2])
    }

    @Test("stops when cancelled")
    func cancelled() {
        var calls = 0
        let cancelAfterFirstPage = {
            calls += 1
            return calls > 1
        }
        let match = DocumentSearch.next(
            "cat", caseSensitive: false, after: TextPosition(page: 1, index: 0), forward: true,
            pageCount: pages.count, text: { pages[$0] }, isCancelled: cancelAfterFirstPage)
        #expect(match == nil)
    }
}
