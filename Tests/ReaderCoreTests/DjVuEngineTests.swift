import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("DjVu engine")
struct DjVuEngineTests {
    @Test("opens a multi-page document with positive page sizes")
    func geometry() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("lizard2002.djvu"))

        #expect(engine.pageCount > 0)
        for index in 0..<engine.pageCount {
            let size = try engine.pageSize(at: index)
            #expect(size.width > 100 && size.height > 100, "page \(index): \(size)")
        }
    }

    @Test("renders at no less than the requested resolution", arguments: [0.5, 1.0, 2.0])
    func render(scale: CGFloat) throws {
        let engine = try DjVuEngine(url: try Fixtures.url("lizard2002.djvu"))
        let size = try engine.pageSize(at: 0)

        let image = try engine.render(page: 0, scale: scale)

        #expect(CGFloat(image.width) >= (size.width * scale).rounded(.down))
        #expect(CGFloat(image.height) >= (size.height * scale).rounded(.down))
    }

    @Test(
        "picks the largest subsample that keeps the target resolution",
        arguments: [
            (dpi: 300, scale: 1.0, expected: 4),  // 300 / 72
            (dpi: 300, scale: 2.0, expected: 2),  // 300 / 144
            (dpi: 300, scale: 5.0, expected: 1),  // upscaling: full resolution
            (dpi: 600, scale: 0.5, expected: 16),  // 600 / 36
            (dpi: 300, scale: 0.0, expected: 1),
        ])
    func subsample(dpi: Int, scale: CGFloat, expected: Int) {
        #expect(DjVuEngine.subsample(dpi: dpi, scale: scale) == expected)
    }

    @Test("fails to open a corrupt file")
    func corruptFile() throws {
        let url = try Fixtures.temporaryFile("broken.djvu", contents: Data("AT&TFORMgarbage".utf8))

        #expect(throws: EngineError.self) { try DjVuEngine(url: url) }
    }

    @Test("reports DjVu as the format")
    func metadata() throws {
        #expect(try DjVuEngine(url: try Fixtures.url("lizard2002.djvu")).metadata.format == "DjVu")
    }

    // MARK: - Navigation

    @Test("loads the bookmark outline with page destinations")
    func outline() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("djvu2spec.djvu"))

        let outline = engine.outline()

        #expect(outline.count == 10)
        #expect(outline[0].title.trimmingCharacters(in: .whitespaces) == "Copyright notice")
        #expect(outline[0].destination == .page(0))
        let pages = outline.compactMap { $0.destination?.page }
        #expect(pages.count == outline.count, "every bookmark resolves to a page")
        #expect(pages == pages.sorted(), "bookmarks follow document order")
        #expect(pages.allSatisfy { (0..<engine.pageCount).contains($0) })
    }

    @Test("returns an empty outline when the document has none")
    func noOutline() throws {
        #expect(try DjVuEngine(url: try Fixtures.url("lizard2002.djvu")).outline().isEmpty)
    }

    @Test(
        "resolves link targets like SumatraPDF",
        arguments: [
            ("#1", Destination.page(0)),
            ("#39", .page(38)),
            ("# 3", .page(2)),
            ("#40", nil),
            ("#0", nil),
            ("http://djvu.org", .uri("http://djvu.org")),
            ("mailto:a@b.c", .uri("mailto:a@b.c")),
            ("www.example.com", .uri("www.example.com")),
            ("nonsense", nil),
        ] as [(String, Destination?)])
    func linkTargets(link: String, expected: Destination?) throws {
        let engine = try DjVuEngine(url: try Fixtures.url("djvu2spec.djvu"))
        #expect(engine.destination(forLink: link) == expected)
    }

    @Test("resolves links that name a page component")
    func namedLinkTarget() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("djvu2spec.djvu"))
        let id = try #require(engine.pageID(at: 4))

        #expect(engine.destination(forLink: "#\(id)") == .page(4))
    }

    // MARK: - Text

    @Test("extracts the hidden text layer with line breaks")
    func text() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("djvu2spec.djvu"))
        let size = try engine.pageSize(at: 0)

        let text = try engine.text(onPage: 0)

        #expect(text.string.hasPrefix("SPECIFICATION OF\nDjVu IMAGE COMPRESSION FORMAT\n"))
        let page = CGRect(origin: .zero, size: size)
        #expect(text.rects.filter { !$0.isNull }.allSatisfy { page.insetBy(dx: -1, dy: -1).contains($0) })
        #expect(text.rects.first?.minY ?? 0 < size.height / 3, "title is at the top of the page")
    }

    @Test("returns empty text for pages without a text layer")
    func noText() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("sumatra-test.djvu"))

        #expect(try engine.text(onPage: 0) == .empty)
        #expect(try engine.links(onPage: 0).isEmpty)
    }

    @Test("finds a phrase and highlights it within its line")
    func search() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("djvu2spec.djvu"))
        let text = try engine.text(onPage: 0)

        let matches = TextSearch.matches(of: "image compression", in: text, page: 0)

        let match = try #require(matches.first)
        #expect(text.string(in: match.range) == "IMAGE COMPRESSION")
        #expect(match.rects.count == 1)
    }
}
