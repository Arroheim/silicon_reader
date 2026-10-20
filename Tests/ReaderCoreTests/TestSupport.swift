import CoreGraphics
import CoreText
import Foundation

@testable import ReaderCore

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard
            let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures")
        else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return url
    }

    static func temporaryFile(_ name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}

/// Generates PDFs with exactly known content.
///
/// All geometry passed in is top-left based (like the engines report it) and
/// converted to PDF's bottom-up space while drawing.
struct TestPDF {
    struct Page {
        var size = CGSize(width: 400, height: 300)
        /// Text drawn in 24pt Helvetica; the point is the top-left of the line box.
        var text: [(String, CGPoint)] = []
        var redTopLeftQuarter = false
        var pageLink: (rect: CGRect, toPage: Int)?
        var urlLink: (rect: CGRect, url: URL)?
    }

    var pages: [Page]
    var info: [CFString: Any] = [:]

    static let fontSize: CGFloat = 24

    /// Pages with a solid red square in the top-left quarter, otherwise white.
    static func make(pageSizes: [CGSize]) throws -> URL {
        try TestPDF(pages: pageSizes.map { Page(size: $0, redTopLeftQuarter: true) }).write()
    }

    func write() throws -> URL {
        try Fixtures.temporaryFile("generated.pdf", contents: try draw())
    }

    private func draw() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let ctx = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, Self.fontSize, nil)

        for (index, page) in pages.enumerated() {
            var box = CGRect(origin: .zero, size: page.size)
            let h = page.size.height
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }

            ctx.beginPage(mediaBox: &box)
            if page.redTopLeftQuarter {
                ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                ctx.fill(flip(CGRect(x: 0, y: 0, width: page.size.width / 2, height: h / 2)))
            }
            for (string, origin) in page.text {
                let attributed = NSAttributedString(
                    string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                let line = CTLineCreateWithAttributedString(attributed)
                ctx.textPosition = CGPoint(x: origin.x, y: h - origin.y - CTFontGetAscent(font))
                CTLineDraw(line, ctx)
            }
            // Every page is a named destination, so links can point forward.
            ctx.addDestination("page\(index)" as CFString, at: CGPoint(x: 0, y: h))
            if let link = page.pageLink {
                ctx.setDestination("page\(link.toPage)" as CFString, for: flip(link.rect))
            }
            if let link = page.urlLink {
                ctx.setURL(link.url as CFURL, for: flip(link.rect))
            }
            ctx.endPage()
        }
        ctx.closePDF()
        return data as Data
    }

}

/// Hand-written PDFs for structures Core Graphics cannot produce.
///
/// PDFKit keeps an outline set on `PDFDocument.outlineRoot` in memory but drops
/// it from both `dataRepresentation()` and `write(to:)` on this macOS, so
/// outlines are serialized here directly.
enum RawPDF {
    struct Outline {
        var title: String
        var page: Int
        var children: [Outline] = []
    }

    /// Blank 400x300 pages with the given outline.
    static func withOutline(pageCount: Int, outline: [Outline]) throws -> URL {
        var objects: [String] = []  // objects[i] is object number i + 1
        func reserve() -> Int {
            objects.append("")
            return objects.count
        }

        let catalog = reserve()
        let pagesRoot = reserve()
        let pageRefs = (0..<pageCount).map { _ in reserve() }
        let outlinesRoot = reserve()

        // Returns (first, last, total descendants) object numbers for a sibling list.
        func emit(_ items: [Outline], parent: Int) -> (first: Int, last: Int, count: Int)? {
            guard !items.isEmpty else { return nil }
            let numbers = items.map { _ in reserve() }
            var total = items.count
            for (i, item) in items.enumerated() {
                var dict = "<< /Title (\(item.title)) /Parent \(parent) 0 R"
                dict += " /Dest [\(pageRefs[item.page]) 0 R /XYZ 0 300 null]"
                if i > 0 { dict += " /Prev \(numbers[i - 1]) 0 R" }
                if i < items.count - 1 { dict += " /Next \(numbers[i + 1]) 0 R" }
                if let kids = emit(item.children, parent: numbers[i]) {
                    dict += " /First \(kids.first) 0 R /Last \(kids.last) 0 R /Count \(kids.count)"
                    total += kids.count
                }
                objects[numbers[i] - 1] = dict + " >>"
            }
            return (numbers[0], numbers[numbers.count - 1], total)
        }

        let top = emit(outline, parent: outlinesRoot)
        objects[catalog - 1] = "<< /Type /Catalog /Pages \(pagesRoot) 0 R /Outlines \(outlinesRoot) 0 R >>"
        let kids = pageRefs.map { "\($0) 0 R" }.joined(separator: " ")
        objects[pagesRoot - 1] = "<< /Type /Pages /Kids [\(kids)] /Count \(pageCount) >>"
        for ref in pageRefs {
            objects[ref - 1] = "<< /Type /Page /Parent \(pagesRoot) 0 R /MediaBox [0 0 400 300] >>"
        }
        objects[outlinesRoot - 1] =
            top.map { "<< /Type /Outlines /First \($0.first) 0 R /Last \($0.last) 0 R /Count \($0.count) >>" }
            ?? "<< /Type /Outlines /Count 0 >>"

        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return try Fixtures.temporaryFile("outline.pdf", contents: Data(pdf.utf8))
    }
}

/// RGBA8 snapshot of a CGImage for pixel assertions.
struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.bytes = bytes
    }

    /// (r, g, b) at a top-down coordinate.
    func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
}

extension PageText {
    /// Builds a text layer from lines of words for search tests. Each scalar
    /// gets a 10x10 box laid out on a grid, so merged rects are predictable.
    static func grid(_ lines: [String]) -> PageText {
        var text = PageText()
        for (row, line) in lines.enumerated() {
            if row > 0 { text.appendSeparator("\n") }
            for (col, scalar) in line.unicodeScalars.enumerated() {
                text.append(scalar, rect: CGRect(x: col * 10, y: row * 10, width: 10, height: 10), line: row)
            }
        }
        return text
    }
}
