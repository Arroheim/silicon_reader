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

    public var supportsRegionRendering: Bool { true }

    public func render(page index: Int, scale: CGFloat, region: CGRect?) throws -> CGImage {
        try checkPage(index)
        let raw: UnsafeMutablePointer<sr_image>?
        if let region {
            var area = sr_rect(
                x0: Float(region.minX), y0: Float(region.minY), x1: Float(region.maxX), y1: Float(region.maxY))
            raw = sr_doc_render(doc, Int32(index), Float(scale), &area)
        } else {
            raw = sr_doc_render(doc, Int32(index), Float(scale), nil)
        }
        guard let raw else {
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

    public func contentBox(at index: Int) -> CGRect? {
        guard (0..<pageCount).contains(index) else { return nil }
        var box = sr_rect()
        guard sr_doc_content_box(doc, Int32(index), &box) == 0 else { return nil }
        return Self.rect(box)
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

    // MARK: - Annotations

    public var supportsAnnotations: Bool { sr_doc_supports_annotations(doc) != 0 }

    public var hasUnsavedChanges: Bool { sr_doc_has_unsaved_changes(doc) != 0 }

    public func annotations(onPage index: Int) throws -> [PageAnnotation] {
        try checkPage(index)
        guard let raw = sr_doc_page_annots(doc, Int32(index)) else {
            throw EngineError.annotationFailed(page: index)
        }
        defer { sr_annots_free(raw) }
        return UnsafeBufferPointer(start: raw.pointee.items, count: Int(raw.pointee.count)).map { item in
            PageAnnotation(
                index: Int(item.index), kind: Self.kind(item.kind), rect: Self.rect(item.rect),
                contents: item.contents.map { String(cString: $0) } ?? "")
        }
    }

    public func addMarkup(_ kind: AnnotationKind, rects: [CGRect], onPage index: Int) throws -> Int {
        try checkPage(index)
        guard kind.isTextMarkup, !rects.isEmpty else { throw EngineError.annotationFailed(page: index) }
        let areas = rects.map {
            sr_rect(x0: Float($0.minX), y0: Float($0.minY), x1: Float($0.maxX), y1: Float($0.maxY))
        }
        return try created(
            sr_doc_add_markup(doc, Int32(index), Self.rawKind(kind), areas, Int32(areas.count)), page: index)
    }

    public func addNote(_ text: String, at point: CGPoint, onPage index: Int) throws -> Int {
        try checkPage(index)
        let at = sr_point(x: Float(point.x), y: Float(point.y))
        return try created(sr_doc_add_note(doc, Int32(index), at, text), page: index)
    }

    public func addFreehand(strokes: [[CGPoint]], onPage index: Int) throws -> Int {
        try checkPage(index)
        let strokes = strokes.filter { !$0.isEmpty }
        guard !strokes.isEmpty else { throw EngineError.annotationFailed(page: index) }
        let points = strokes.joined().map { sr_point(x: Float($0.x), y: Float($0.y)) }
        let lengths = strokes.map { Int32($0.count) }
        return try created(sr_doc_add_ink(doc, Int32(index), points, lengths, Int32(lengths.count)), page: index)
    }

    public func setContents(_ text: String, ofAnnotation annotation: Int, onPage index: Int) throws {
        try checkPage(index)
        guard sr_doc_set_annot_contents(doc, Int32(index), Int32(annotation), text) == 0 else {
            throw EngineError.annotationFailed(page: index)
        }
    }

    public func removeAnnotation(_ annotation: Int, onPage index: Int) throws {
        try checkPage(index)
        guard sr_doc_delete_annot(doc, Int32(index), Int32(annotation)) == 0 else {
            throw EngineError.annotationFailed(page: index)
        }
    }

    /// MuPDF can't write over a file it is reading, so the document goes to a
    /// temporary file that then replaces `target`. The open document keeps
    /// reading the old file, which stays alive until it is closed.
    public func save(to target: URL) throws {
        let folder = target.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var err = [CChar](repeating: 0, count: 512)
        let overSelf = target.standardizedFileURL == url.standardizedFileURL
        guard sr_doc_save(doc, temporary.path, overSelf ? 1 : 0, &err, err.count) == 0 else {
            throw EngineError.saveFailed(target, reason: Self.string(err))
        }
        guard rename(temporary.path, target.path) == 0 else {
            throw EngineError.saveFailed(target, reason: String(cString: strerror(errno)))
        }
    }

    private func created(_ index: Int32, page: Int) throws -> Int {
        guard index >= 0 else { throw EngineError.annotationFailed(page: page) }
        return Int(index)
    }

    private static func kind(_ raw: sr_annot_kind) -> AnnotationKind {
        switch raw {
        case SR_ANNOT_HIGHLIGHT: .highlight
        case SR_ANNOT_UNDERLINE: .underline
        case SR_ANNOT_STRIKEOUT: .strikeOut
        case SR_ANNOT_NOTE: .note
        case SR_ANNOT_INK: .freehand
        default: .other
        }
    }

    private static func rawKind(_ kind: AnnotationKind) -> sr_annot_kind {
        switch kind {
        case .highlight: SR_ANNOT_HIGHLIGHT
        case .underline: SR_ANNOT_UNDERLINE
        case .strikeOut: SR_ANNOT_STRIKEOUT
        case .note: SR_ANNOT_NOTE
        case .freehand: SR_ANNOT_INK
        case .other: SR_ANNOT_OTHER
        }
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
