import Foundation
import Testing

@testable import ReaderCore

@Suite("Print layout")
struct PrintLayoutTests {
    private let paper = CGRect(x: 18, y: 18, width: 576, height: 756)  // Letter minus 1/4" margins

    @Test("fits a portrait page into the printable area, centred")
    func fitPortrait() {
        let placement = PrintLayout.place(pageSize: CGSize(width: 612, height: 792), in: paper)

        #expect(!placement.rotated)
        #expect(abs(placement.rect.height - 745.4) < 0.1)  // 576 / 612 * 792
        #expect(abs(placement.rect.midX - paper.midX) < 0.001 && abs(placement.rect.midY - paper.midY) < 0.001)
    }

    @Test("rotates a landscape page onto portrait paper")
    func autoRotate() {
        let placement = PrintLayout.place(pageSize: CGSize(width: 792, height: 612), in: paper)

        #expect(placement.rotated)
        #expect(placement.rect.width < placement.rect.height)
    }

    @Test("keeps orientation when auto-rotation is off")
    func noAutoRotate() {
        let placement = PrintLayout.place(pageSize: CGSize(width: 792, height: 612), in: paper, autoRotate: false)

        #expect(!placement.rotated)
        #expect(placement.rect.width == paper.width)
    }

    @Test("shrink never enlarges a small page, fit does")
    func scaling() {
        let small = CGSize(width: 200, height: 300)

        #expect(PrintLayout.place(pageSize: small, in: paper, scaling: .shrink).rect.size == small)
        #expect(PrintLayout.place(pageSize: small, in: paper, scaling: .fit).rect.width > 200)
    }
}

@Suite("Document properties")
struct DocumentPropertiesTests {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    @Test("lists known values in SumatraPDF's order and skips absent ones")
    func rows() {
        var meta = DocumentMetadata(format: "PDF 1.7")
        meta.title = "Spec"
        meta.author = "AT&T"
        meta.creationDate = Date(timeIntervalSince1970: 0)

        let rows = DocumentProperties.rows(
            url: URL(fileURLWithPath: "/docs/spec.pdf"), fileSize: 2_457_600, metadata: meta, pageCount: 39,
            firstPageSize: CGSize(width: 612, height: 792), locale: locale, timeZone: utc)

        #expect(
            rows.map(\.label) == [
                "File", "Title", "Author", "Created", "Format", "File Size", "Number of Pages", "Page Size",
            ])
        #expect(rows.first { $0.label == "Created" }?.value.contains("1970") == true)
        #expect(rows.first { $0.label == "File Size" }?.value.hasSuffix("(2,457,600 Bytes)") == true)
        #expect(rows.first { $0.label == "Page Size" }?.value == "8.50 × 11.00 in (Letter)")
    }

    @Test("uses millimetres in metric locales and recognizes A4 either way round")
    func metricPaper() {
        let a4Landscape = CGSize(width: 842, height: 595)
        let size = DocumentProperties.formatPageSize(a4Landscape, locale: Locale(identifier: "ru_RU"))
        #expect(size == "297 × 210 mm (A4)")
        #expect(DocumentProperties.paperName(for: CGSize(width: 500, height: 500)) == nil)
    }

    @Test("formats rows for the clipboard")
    func clipboardText() {
        let rows = [DocumentProperties.Row(label: "Title", value: "Spec"), .init(label: "Author", value: "Me")]
        #expect(DocumentProperties.text(rows) == "Title:\tSpec\nAuthor:\tMe")
    }
}

@Suite("Command palette")
struct PaletteQueryTests {
    @Test(
        "picks the list from SumatraPDF's prefix characters",
        arguments: [
            (">zoom", PaletteQuery.Source.commands, ["zoom"]), ("@spec", .tabs, ["spec"]), ("#", .history, []),
            ("$intro", .favorites, ["intro"]), ("%2 def", .outline, ["2", "def"]),
        ] as [(String, PaletteQuery.Source, [String])])
    func prefixes(text: String, source: PaletteQuery.Source, words: [String]) {
        let query = PaletteQuery(text)
        #expect(query.source == source)
        #expect(query.words == words)
    }

    @Test("without a prefix searches everything")
    func noPrefix() {
        #expect(PaletteQuery("Fit Width").source == nil)
        #expect(PaletteQuery("Fit Width").words == ["fit", "width"])
    }

    @Test("needs every word, in any order")
    func allWords() {
        let query = PaletteQuery("width fit")
        #expect(query.score(title: "Fit Width") != nil)
        #expect(query.score(title: "Fit Page") == nil)
        #expect(PaletteQuery("djvu").score(title: "spec.djvu", detail: "/docs") != nil)
        #expect(PaletteQuery("docs").score(title: "spec.djvu", detail: "/docs") != nil, "detail line counts")
    }

    @Test("ranks title starts above matches inside words")
    func ranking() {
        let titles = ["Show Page Info", "Zoom Out", "Rotate Left", "Zoom In"]

        let ranked = PaletteQuery("zo").filter(titles, title: { $0 })

        #expect(ranked == ["Zoom Out", "Zoom In"], "ties keep table order")
        #expect(PaletteQuery("in").filter(titles, title: { $0 }).first == "Show Page Info", "word start beats …")
        #expect(PaletteQuery("").filter(titles, title: { $0 }) == titles)
    }
}
