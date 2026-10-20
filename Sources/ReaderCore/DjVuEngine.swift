import CDjVu
import CoreGraphics
import Foundation

/// DjVu via the vendored plain-C djvudec decoder.
// @unchecked: djvudec is safe for concurrent renders on one document once the
// context is created with lock/unlock hooks, which we always supply. Metadata
// calls (text, links, outline) are additionally serialized by `infoLock`.
public final class DjVuEngine: DocumentEngine, @unchecked Sendable {
    public let url: URL
    public let pageCount: Int
    public let metadata = DocumentMetadata(format: "DjVu")
    private let data: Data
    private let ctx: OpaquePointer
    private let doc: OpaquePointer
    private let lock: UnsafeMutablePointer<pthread_mutex_t>
    private let infoLock = NSLock()

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

    // MARK: - Pages

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

    /// Points per full-resolution page pixel.
    private func pointsPerPixel(at index: Int) throws -> CGFloat {
        72.0 / CGFloat(try pixelGeometry(at: index).dpi)
    }

    public func pageSize(at index: Int) throws -> CGSize {
        let geo = try pixelGeometry(at: index)
        let k = 72.0 / CGFloat(geo.dpi)
        return CGSize(width: CGFloat(geo.width) * k, height: CGFloat(geo.height) * k)
    }

    public func pageLabel(at index: Int) -> String? {
        guard (0..<pageCount).contains(index) else { return nil }
        infoLock.lock()
        defer { infoLock.unlock() }
        guard let title = djvu_doc_page_title(doc, Int32(index)).map({ String(cString: $0) }) else { return nil }
        let id = djvu_doc_page_id(doc, Int32(index)).map { String(cString: $0) }
        // Titles default to the component file name, which is not a meaningful label.
        return title.isEmpty || title == id || title == String(index + 1) ? nil : title
    }

    /// djvudec decodes whole pages only.
    public var supportsRegionRendering: Bool { false }

    /// Not computed: SumatraPDF derives it from a rendered bitmap, which is
    /// costly for large scans. Fit content falls back to the page box.
    public func contentBox(at index: Int) -> CGRect? { nil }

    public func render(page index: Int, scale: CGFloat, region: CGRect?) throws -> CGImage {
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

    // MARK: - Navigation

    public func outline() -> [OutlineItem] {
        infoLock.lock()
        defer { infoLock.unlock() }
        guard let root = djvu_doc_outline(doc) else { return [] }
        defer { djvu_outline_destroy(ctx, root) }
        return convert(root.pointee)
    }

    private func convert(_ node: djvu_outline_item) -> [OutlineItem] {
        UnsafeBufferPointer(start: node.children, count: Int(node.nchildren)).map { child in
            let destination: Destination? =
                child.page_no >= 0
                ? .page(Int(child.page_no)) : child.url.flatMap { resolveLink(String(cString: $0)) }
            return OutlineItem(
                title: child.title.map { String(cString: $0) } ?? "",
                destination: destination,
                children: convert(child))
        }
    }

    public func links(onPage index: Int) throws -> [PageLink] {
        let k = try pointsPerPixel(at: index)
        infoLock.lock()
        defer { infoLock.unlock() }
        guard let raw = djvu_page_get_links(doc, Int32(index)) else { return [] }
        defer { djvu_page_links_destroy(ctx, raw) }
        return UnsafeBufferPointer(start: raw.pointee.links, count: Int(raw.pointee.nlinks)).compactMap { link in
            guard let url = link.url, let destination = resolveLink(String(cString: url)) else { return nil }
            let rect = CGRect(
                x: CGFloat(link.x) * k, y: CGFloat(link.y) * k, width: CGFloat(link.w) * k, height: CGFloat(link.h) * k)
            return PageLink(rect: rect, destination: destination)
        }
    }

    func destination(forLink link: String) -> Destination? {
        infoLock.lock()
        defer { infoLock.unlock() }
        return resolveLink(link)
    }

    func pageID(at index: Int) -> String? {
        infoLock.lock()
        defer { infoLock.unlock() }
        return djvu_doc_page_id(doc, Int32(index)).map { String(cString: $0) }
    }

    /// DjVu link targets, following SumatraPDF: `#12` is a 1-based page number,
    /// `#name` a component id; anything that looks like a URL is external.
    /// Caller must hold `infoLock`.
    private func resolveLink(_ link: String) -> Destination? {
        let target = link.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if link.hasPrefix("#") || !Self.couldBeURL(link) {
            if let number = Int(target), (1...pageCount).contains(number) {
                return .page(number - 1)
            }
            let page = djvu_doc_page_by_name(doc, target)
            if page >= 0 {
                return .page(Int(page))
            }
        }
        return Self.couldBeURL(link) ? .uri(link) : nil
    }

    private static func couldBeURL(_ link: String) -> Bool {
        let lower = link.lowercased()
        return ["http:", "https:", "mailto:"].contains { lower.hasPrefix($0) }
            || (!link.hasPrefix("#") && link.contains("."))
    }

    // MARK: - Text

    public func text(onPage index: Int) throws -> PageText {
        let k = try pointsPerPixel(at: index)
        infoLock.lock()
        defer { infoLock.unlock() }
        guard let zones = djvu_page_text_get_zones(doc, Int32(index)) else { return .empty }
        defer { djvu_text_zones_destroy(ctx, zones) }
        guard let root = zones.pointee.root else { return .empty }

        var text = PageText()
        var line = 0
        Self.collect(root.pointee, scale: k, into: &text, line: &line)
        return text
    }

    /// Mirrors SumatraPDF: leaf zones (usually words) are split evenly into
    /// per-character boxes; words are separated by spaces and lines by newlines.
    private static func collect(_ zone: djvu_text_zone, scale k: CGFloat, into text: inout PageText, line: inout Int) {
        if zone.nchildren > 0 {
            for child in UnsafeBufferPointer(start: zone.children, count: Int(zone.nchildren)) {
                collect(child, scale: k, into: &text, line: &line)
                if child.type == DJVU_ZONE_WORD {
                    text.appendSeparator(" ")
                } else if child.type == DJVU_ZONE_LINE {
                    text.appendSeparator("\n")
                    line += 1
                }
            }
            return
        }
        guard let raw = zone.text else { return }
        let scalars = Array(String(cString: raw).unicodeScalars)
        guard !scalars.isEmpty else { return }
        let x = CGFloat(zone.x) * k
        let width = CGFloat(zone.w) * k
        let n = CGFloat(scalars.count)
        for (i, scalar) in scalars.enumerated() {
            let x0 = x + width * CGFloat(i) / n
            let x1 = x + width * CGFloat(i + 1) / n
            let rect = CGRect(x: x0, y: CGFloat(zone.y) * k, width: x1 - x0, height: CGFloat(zone.h) * k)
            text.append(scalar, rect: rect, line: line)
        }
    }
}
