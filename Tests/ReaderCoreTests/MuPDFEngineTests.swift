import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("MuPDF engine")
struct MuPDFEngineTests {
    @Test("reports page count and per-page sizes in points")
    func geometry() throws {
        let url = try TestPDF.make(pageSizes: [CGSize(width: 612, height: 792), CGSize(width: 300, height: 400)])
        let engine = try MuPDFEngine(url: url)

        #expect(engine.pageCount == 2)
        #expect(try engine.pageSize(at: 0) == CGSize(width: 612, height: 792))
        #expect(try engine.pageSize(at: 1) == CGSize(width: 300, height: 400))
    }

    @Test("renders at the requested scale, top-down", arguments: [1.0, 2.0])
    func render(scale: CGFloat) throws {
        let url = try TestPDF.make(pageSizes: [CGSize(width: 200, height: 100)])
        let engine = try MuPDFEngine(url: url)

        let pixels = Pixels(try engine.render(page: 0, scale: scale))

        #expect(pixels.width == Int(200 * scale))
        #expect(pixels.height == Int(100 * scale))
        let topLeft = pixels.rgb(x: pixels.width / 4, y: pixels.height / 4)
        let bottomRight = pixels.rgb(x: pixels.width * 3 / 4, y: pixels.height * 3 / 4)
        #expect(topLeft.r > 200 && topLeft.g < 60 && topLeft.b < 60, "expected red, got \(topLeft)")
        #expect(bottomRight == (255, 255, 255), "expected white, got \(bottomRight)")
    }

    @Test("rejects out-of-range pages")
    func invalidPage() throws {
        let engine = try MuPDFEngine(url: try TestPDF.make(pageSizes: [CGSize(width: 100, height: 100)]))

        #expect(throws: EngineError.invalidPage(1)) { try engine.render(page: 1, scale: 1) }
        #expect(throws: EngineError.invalidPage(-1)) { try engine.pageSize(at: -1) }
        #expect(throws: EngineError.invalidPage(1)) { try engine.text(onPage: 1) }
        #expect(throws: EngineError.invalidPage(1)) { try engine.links(onPage: 1) }
    }

    @Test("fails to open a corrupt file with a reason")
    func corruptFile() throws {
        let url = try Fixtures.temporaryFile("broken.pdf", contents: Data("not a pdf".utf8))

        #expect {
            try MuPDFEngine(url: url)
        } throws: { error in
            guard case .openFailed(_, let reason) = error as? EngineError else { return false }
            return !reason.isEmpty
        }
    }

    // MARK: - Document information

    @Test("reads document info")
    func metadata() throws {
        let pdf = TestPDF(
            pages: [.init()],
            info: [kCGPDFContextTitle: "Test Title", kCGPDFContextAuthor: "Arroheim", kCGPDFContextSubject: "Engines"])
        let engine = try MuPDFEngine(url: try pdf.write())

        let meta = engine.metadata
        #expect(meta.title == "Test Title")
        #expect(meta.author == "Arroheim")
        #expect(meta.subject == "Engines")
        #expect(meta.format?.hasPrefix("PDF") == true)
        #expect(meta.encryption == nil)
        let created = try #require(meta.creationDate)
        #expect(abs(created.timeIntervalSinceNow) < 600)
    }

    @Test("requires the right password for encrypted documents")
    func password() throws {
        let pdf = TestPDF(
            pages: [.init()],
            info: [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner"])
        let url = try pdf.write()

        #expect(throws: EngineError.passwordRequired(url)) { try MuPDFEngine(url: url) }
        #expect(throws: EngineError.wrongPassword(url)) { try MuPDFEngine(url: url, password: "nope") }
        let engine = try MuPDFEngine(url: url, password: "secret")
        #expect(engine.pageCount == 1)
        #expect(engine.metadata.encryption != nil)
    }

    @Test("has no page labels when pages are plainly numbered")
    func pageLabels() throws {
        let engine = try MuPDFEngine(url: try TestPDF(pages: [.init(), .init()]).write())

        #expect(engine.pageLabel(at: 0) == nil)
        #expect(engine.pageLabel(at: 5) == nil)
    }

    // MARK: - Navigation

    @Test("loads a nested outline with page destinations")
    func outline() throws {
        let url = try RawPDF.withOutline(
            pageCount: 3,
            outline: [
                .init(title: "Chapter 1", page: 0, children: [.init(title: "Section 1.1", page: 1)]),
                .init(title: "Chapter 2", page: 2),
            ])
        let outline = try MuPDFEngine(url: url).outline()

        try #require(outline.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(outline.map { $0.destination?.page } == [0, 2])
        try #require(outline[0].children.map(\.title) == ["Section 1.1"])
        #expect(outline[0].children[0].destination?.page == 1)
        #expect(outline[0].children[0].children.isEmpty)
    }

    @Test("returns an empty outline when the document has none")
    func noOutline() throws {
        #expect(try MuPDFEngine(url: try TestPDF(pages: [.init()]).write()).outline().isEmpty)
    }

    @Test("resolves internal and external links with top-left rects")
    func links() throws {
        let internalRect = CGRect(x: 20, y: 30, width: 100, height: 20)
        let externalRect = CGRect(x: 20, y: 200, width: 150, height: 20)
        let url = URL(string: "https://example.com/doc")!
        var first = TestPDF.Page()
        first.pageLink = (internalRect, 1)
        first.urlLink = (externalRect, url)
        let engine = try MuPDFEngine(url: try TestPDF(pages: [first, .init()]).write())

        let links = try engine.links(onPage: 0)

        #expect(links.count == 2)
        let pageLink = try #require(links.first { $0.destination.page == 1 })
        #expect(pageLink.rect.isApproximately(internalRect))
        let uriLink = try #require(links.first { $0.destination == .uri(url.absoluteString) })
        #expect(uriLink.rect.isApproximately(externalRect))
        #expect(try engine.links(onPage: 1).isEmpty)
    }

    // MARK: - Text

    @Test("extracts text with line breaks and glyph boxes")
    func text() throws {
        var page = TestPDF.Page()
        page.text = [("Hello World", CGPoint(x: 40, y: 50)), ("Second line", CGPoint(x: 40, y: 120))]
        let engine = try MuPDFEngine(url: try TestPDF(pages: [page]).write())

        let text = try engine.text(onPage: 0)

        #expect(text.string == "Hello World\nSecond line")
        let h = try #require(text.rects.first)
        #expect(abs(h.minX - 40) < 2, "H starts at \(h)")
        #expect(h.minY >= 45 && h.maxY <= 50 + TestPDF.fontSize * 1.3, "H box \(h)")
        #expect(Set(text.lines).count == 2)
    }

    @Test("finds text on a rendered page")
    func search() throws {
        var page = TestPDF.Page()
        page.text = [("The quick brown", CGPoint(x: 40, y: 50)), ("fox jumps", CGPoint(x: 40, y: 120))]
        let engine = try MuPDFEngine(url: try TestPDF(pages: [page]).write())
        let text = try engine.text(onPage: 0)

        let matches = TextSearch.matches(of: "BROWN fox", in: text, page: 0)

        let match = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(text.string(in: match.range) == "brown\nfox")
        #expect(match.rects.count == 2, "one highlight box per line")
        #expect(match.rects[0].minY < match.rects[1].minY)
    }
}

extension Destination {
    var page: Int? {
        if case .page(let index, _) = self { index } else { nil }
    }
}

extension CGRect {
    func isApproximately(_ other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
