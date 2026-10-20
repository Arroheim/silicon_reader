import CMuPDF
import CoreGraphics
import Foundation

/// PDF (and anything else MuPDF opens) via the CMuPDF shim.
// @unchecked: the shim serializes every call on a document behind its own mutex.
public final class MuPDFEngine: DocumentEngine, @unchecked Sendable {
    public let url: URL
    public let pageCount: Int
    private let doc: OpaquePointer

    public init(url: URL) throws {
        var err = [CChar](repeating: 0, count: 512)
        guard let doc = sr_doc_open(url.path, &err, err.count) else {
            let message = err.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            throw EngineError.openFailed(url, reason: String(decoding: message, as: UTF8.self))
        }
        let count = sr_doc_page_count(doc)
        guard count > 0 else {
            sr_doc_close(doc)
            throw EngineError.openFailed(url, reason: "document has no pages")
        }
        self.url = url
        self.doc = doc
        self.pageCount = Int(count)
    }

    deinit {
        sr_doc_close(doc)
    }

    public func pageSize(at index: Int) throws -> CGSize {
        try checkPage(index)
        var width: Float = 0
        var height: Float = 0
        guard sr_doc_page_size(doc, Int32(index), &width, &height) == 0 else {
            throw EngineError.invalidPage(index)
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
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
}
