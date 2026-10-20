import CoreGraphics
import Testing

@testable import ReaderCore

@Suite("Text search")
struct TextSearchTests {
    @Test("matches case-insensitively by default")
    func caseInsensitive() {
        let text = PageText.grid(["Hello World"])

        let matches = TextSearch.matches(of: "world", in: text, page: 3)

        #expect(matches.map(\.range) == [6..<11])
        #expect(matches.first?.page == 3)
    }

    @Test("respects case when asked")
    func caseSensitive() {
        let text = PageText.grid(["Hello World"])

        #expect(TextSearch.matches(of: "world", in: text, page: 0, caseSensitive: true).isEmpty)
        #expect(TextSearch.matches(of: "World", in: text, page: 0, caseSensitive: true).count == 1)
    }

    @Test("folds case for non-Latin scripts")
    func unicode() {
        let text = PageText.grid(["Привет, МИР"])

        #expect(TextSearch.matches(of: "мир", in: text, page: 0).map(\.range) == [8..<11])
    }

    @Test("matches a phrase across a line break with one box per line")
    func acrossLines() {
        let text = PageText.grid(["the quick", "brown fox"])

        let match = TextSearch.matches(of: "quick  brown", in: text, page: 0).first

        #expect(match?.range == 4..<15)
        #expect(
            match?.rects == [
                CGRect(x: 40, y: 0, width: 50, height: 10),
                CGRect(x: 0, y: 10, width: 50, height: 10),
            ])
    }

    @Test("finds every non-overlapping occurrence")
    func multiple() {
        let text = PageText.grid(["aaaa aa"])

        #expect(TextSearch.matches(of: "aa", in: text, page: 0).map(\.range) == [0..<2, 2..<4, 5..<7])
    }

    @Test("ignores surrounding whitespace in the query", arguments: ["  fox", "fox\n", "\tfox  "])
    func trimsQuery(query: String) {
        let text = PageText.grid(["brown fox"])

        #expect(TextSearch.matches(of: query, in: text, page: 0).map(\.range) == [6..<9])
    }

    @Test("returns nothing for empty queries or missing text", arguments: ["", "   ", "\n"])
    func emptyQuery(query: String) {
        #expect(TextSearch.matches(of: query, in: .grid(["text"]), page: 0).isEmpty)
        #expect(TextSearch.matches(of: "text", in: .empty, page: 0).isEmpty)
    }
}

@Suite("Page text")
struct PageTextTests {
    @Test("does not stack separators")
    func separators() {
        var text = PageText()
        text.appendSeparator(" ")
        text.append("a", rect: CGRect(x: 0, y: 0, width: 1, height: 1), line: 0)
        text.appendSeparator(" ")
        text.appendSeparator(" ")

        #expect(text.string == "a ")
    }

    @Test("a line break replaces a synthesized word space")
    func lineBreakReplacesSpace() {
        var text = PageText()
        text.append("a", rect: CGRect(x: 0, y: 0, width: 1, height: 1), line: 0)
        text.appendSeparator(" ")
        text.appendSeparator("\n")

        #expect(text.string == "a\n")
        #expect(text.rects.count == 2)
    }

    @Test("keeps a real space glyph before a line break")
    func realSpaceKept() {
        var text = PageText()
        text.append("a", rect: CGRect(x: 0, y: 0, width: 1, height: 1), line: 0)
        text.append(" ", rect: CGRect(x: 1, y: 0, width: 1, height: 1), line: 0)
        text.appendSeparator("\n")

        #expect(text.string == "a ")
    }

    @Test("merges boxes per line and skips separators")
    func rectsForRange() {
        let text = PageText.grid(["ab", "cd"])

        #expect(
            text.rects(for: 0..<5) == [
                CGRect(x: 0, y: 0, width: 20, height: 10),
                CGRect(x: 0, y: 10, width: 20, height: 10),
            ])
        #expect(text.rects(for: 2..<3).isEmpty, "the separator alone has no box")
    }

    @Test("ignores whitespace glyphs but still spans the gap between words")
    func whitespaceGlyphs() {
        let text = PageText.grid(["a b", "   "])

        #expect(text.rects(for: 0..<3) == [CGRect(x: 0, y: 0, width: 30, height: 10)])
        #expect(text.rects(for: 4..<7).isEmpty, "a line of spaces gets no highlight")
    }
}
