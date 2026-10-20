import CDjVu
import CoreGraphics
import Foundation

/// DjVu via the vendored plain-C djvudec decoder.
// @unchecked: djvudec is safe for concurrent renders on one document once the
// context is created with lock/unlock hooks, which we always supply.
public final class DjVuEngine: DocumentEngine, @unchecked Sendable {
    public let url: URL
    public let pageCount: Int
    private let data: Data
    private let ctx: OpaquePointer
    private let doc: OpaquePointer
    private let lock: UnsafeMutablePointer<pthread_mutex_t>

    private static let initOnce: Void = djvu_init()

    public init(url: URL) throws {
        _ = Self.initOnce
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw EngineError.openFailed(url, reason: error.localizedDescription)
        }

        let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(lock, nil)
        guard
            let ctx = djvu_ctx_new(
                nil, nil,
                { user, _ in pthread_mutex_lock(user!.assumingMemoryBound(to: pthread_mutex_t.self)) },
                { user, _ in pthread_mutex_unlock(user!.assumingMemoryBound(to: pthread_mutex_t.self)) },
                nil, lock)
        else {
            pthread_mutex_destroy(lock)
            lock.deallocate()
            throw EngineError.openFailed(url, reason: "cannot create djvu context")
        }

        // djvu_doc_open does not copy: `data` is retained by self for the doc's lifetime.
        let doc = data.withUnsafeBytes { buf in
            djvu_doc_open(ctx, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        guard let doc, djvu_doc_page_count(doc) > 0 else {
            if let doc { djvu_doc_close(doc) }
            djvu_ctx_free(ctx)
            pthread_mutex_destroy(lock)
            lock.deallocate()
            throw EngineError.openFailed(url, reason: "not a valid DjVu document")
        }

        self.url = url
        self.data = data
        self.lock = lock
        self.ctx = ctx
        self.doc = doc
        self.pageCount = Int(djvu_doc_page_count(doc))
    }

    deinit {
        djvu_doc_close(doc)
        djvu_ctx_free(ctx)
        pthread_mutex_destroy(lock)
        lock.deallocate()
    }

    /// Full-resolution geometry in pixels plus the page DPI.
    private func pixelGeometry(at index: Int) throws -> (width: Int, height: Int, dpi: Int) {
        try checkPage(index)
        var info = djvu_page_info()
        var render = djvu_render_info()
        guard djvu_doc_page_info(doc, Int32(index), &info) == 0,
            djvu_page_render_info(doc, Int32(index), 1, &render) == 0
        else {
            throw EngineError.invalidPage(index)
        }
        let dpi = info.dpi > 0 ? Int(info.dpi) : 300
        return (Int(render.width), Int(render.height), dpi)
    }

    public func pageSize(at index: Int) throws -> CGSize {
        let geo = try pixelGeometry(at: index)
        let pointsPerPixel = 72.0 / CGFloat(geo.dpi)
        return CGSize(width: CGFloat(geo.width) * pointsPerPixel, height: CGFloat(geo.height) * pointsPerPixel)
    }

    public func render(page index: Int, scale: CGFloat) throws -> CGImage {
        let geo = try pixelGeometry(at: index)
        let subsample = Self.subsample(dpi: geo.dpi, scale: scale)
        guard let raw = djvu_page_render(doc, Int32(index), Int32(subsample)) else {
            throw EngineError.renderFailed(page: index)
        }
        defer { djvu_image_destroy(ctx, raw) }
        let img = raw.pointee
        guard
            let image = makeImage(
                width: Int(img.width), height: Int(img.height), stride: Int(img.stride),
                components: Int(img.format.rawValue), pixels: img.data)
        else {
            throw EngineError.renderFailed(page: index)
        }
        return image
    }

    /// Largest integer reduction that still yields at least the requested resolution.
    static func subsample(dpi: Int, scale: CGFloat) -> Int {
        let targetDPI = 72.0 * scale
        guard targetDPI > 0 else { return 1 }
        return max(1, Int((CGFloat(dpi) / targetDPI).rounded(.down)))
    }
}
