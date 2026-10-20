import CMuPDF
import CoreGraphics
import Foundation

/// PDF (and anything else MuPDF opens) via the CMuPDF shim.
// @unchecked: the shim serializes every call on a document behind its own mutex.
public final class MuPDFEngine: DocumentEngine, @unchecked Sendable {
    public let url: URL
    public let pageCount: Int
    public let metadata: DocumentMetadata
    private let doc: OpaquePointer

    /// Opens a document; `password` is tried only if the file is encrypted.
    public init(url: URL, password: String? = nil) throws {
        var err = [CChar](repeating: 0, count: 512)
        guard let doc = sr_doc_open(url.path, &err, err.count) else {
            throw EngineError.openFailed(url, reason: Self.string(err))
        }
        if sr_doc_needs_password(doc) != 0 {
            guard let password else {
                sr_doc_close(doc)
                throw EngineError.passwordRequired(url)
            }
            guard sr_doc_authenticate(doc, password) != 0 else {
                sr_doc_close(doc)
                throw EngineError.wrongPassword(url)
            }
        }
        let count = sr_doc_page_count(doc)
        guard count > 0 else {
            sr_doc_close(doc)
            throw EngineError.openFailed(url, reason: "document has no pages")
        }
        self.url = url
        self.doc = doc
        self.pageCount = Int(count)
        self.metadata = Self.readMetadata(doc)
    }

    deinit {
        sr_doc_close(doc)
    }

    // MARK: - Pages

    public func pageSize(at index: Int) throws -> CGSize {
        try checkPage(index)
        var width: Float = 0
        var height: Float = 0
        guard sr_doc_page_size(doc, Int32(index), &width, &height) == 0 else {
            throw EngineError.invalidPage(index)
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    public func pageLabel(at index: Int) -> String? {
        guard (0..<pageCount).contains(index) else { return nil }
        var buf = [CChar](repeating: 0, count: 128)
        guard sr_doc_page_label(doc, Int32(index), &buf, Int32(buf.count)) == 0 else { return nil }
        let label = Self.string(buf)
        return label == String(index + 1) ? nil : label
    }

    public func render(page index: Int, scale: CGFloat) throws -> CGImage {
        try checkPage(index)
        guard let raw = sr_doc_render(doc, Int32(index), Float(scale)) else {
            throw EngineError.renderFailed(page: index)
        }
        defer { sr_image_free(raw) }
        let img = raw.pointee
        guard
            let image = makeImage(
                width: Int(img.width), height: Int(img.height), stride: Int(img.stride),
                components: 3, pixels: img.data)
        else {
            throw EngineError.renderFailed(page: index)
        }
        return image
    }

    // MARK: - Navigation

    public func outline() -> [OutlineItem] {
        guard let root = sr_doc_outline(doc) else { return [] }
        defer { sr_outline_free(root) }
        return Self.convert(root.pointee)
    }

    public func links(onPage index: Int) throws -> [PageLink] {
        try checkPage(index)
        guard let raw = sr_doc_page_links(doc, Int32(index)) else { return [] }
        defer { sr_links_free(raw) }
        let items = UnsafeBufferPointer(start: raw.pointee.items, count: Int(raw.pointee.count))
        return items.compactMap { link in
            Self.destination(link.dest).map { PageLink(rect: Self.rect(link.rect), destination: $0) }
        }
    }

    // MARK: - Text

    public func text(onPage index: Int) throws -> PageText {
        try checkPage(index)
        guard let raw = sr_doc_page_text(doc, Int32(index)) else {
            throw EngineError.textExtractionFailed(page: index)
        }
        defer { sr_text_free(raw) }

        var text = PageText()
        var previousLine: Int?
        for ch in UnsafeBufferPointer(start: raw.pointee.chars, count: Int(raw.pointee.count)) {
            guard let scalar = Unicode.Scalar(ch.codepoint) else { continue }
            let line = Int(ch.line)
            if let previousLine, previousLine != line {
                text.appendSeparator("\n")
            }
            previousLine = line
            text.append(scalar, rect: Self.rect(ch.rect), line: line)
        }
        return text
    }

    // MARK: - Conversions

    private static func string(_ buf: [CChar]) -> String {
        String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func rect(_ r: sr_rect) -> CGRect {
        CGRect(x: CGFloat(r.x0), y: CGFloat(r.y0), width: CGFloat(r.x1 - r.x0), height: CGFloat(r.y1 - r.y0))
    }

    private static func destination(_ dest: sr_dest) -> Destination? {
        if let uri = dest.uri {
            return .uri(String(cString: uri))
        }
        guard dest.page >= 0 else { return nil }
        let point = dest.x.isNaN || dest.y.isNaN ? nil : CGPoint(x: CGFloat(dest.x), y: CGFloat(dest.y))
        return .page(Int(dest.page), point: point)
    }

    private static func convert(_ node: sr_outline) -> [OutlineItem] {
        UnsafeBufferPointer(start: node.children, count: Int(node.count)).map { child in
            OutlineItem(
                title: child.title.map { String(cString: $0) } ?? "",
                destination: destination(child.dest),
                isExpanded: child.is_open != 0,
                children: convert(child))
        }
    }

    private static func readMetadata(_ doc: OpaquePointer) -> DocumentMetadata {
        func value(_ key: String) -> String? {
            var buf = [CChar](repeating: 0, count: 1024)
            guard sr_doc_metadata(doc, key, &buf, buf.count) > 0 else { return nil }
            let s = string(buf).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        var meta = DocumentMetadata(format: value("format"))
        meta.title = value("info:Title")
        meta.author = value("info:Author")
        meta.subject = value("info:Subject")
        meta.keywords = value("info:Keywords")
        meta.creator = value("info:Creator")
        meta.producer = value("info:Producer")
        meta.creationDate = value("info:CreationDate").flatMap(PDFDate.parse)
        meta.modificationDate = value("info:ModDate").flatMap(PDFDate.parse)
        meta.encryption = value("encryption").flatMap { $0 == "None" ? nil : $0 }
        return meta
    }
}
