import Foundation

/// Thread-safe cache of page text layers. Extraction runs on the calling
/// thread; concurrent requests for the same page may both extract once.
public final class TextStore: @unchecked Sendable {
    // @unchecked: `pages` is only touched under `lock`; the engine is Sendable.
    private let engine: any DocumentEngine
    private let lock = NSLock()
    private var pages: [Int: PageText] = [:]

    public init(engine: any DocumentEngine) {
        self.engine = engine
    }

    public var pageCount: Int { engine.pageCount }

    /// Cached text, or nil if the page hasn't been extracted yet.
    public func cached(_ page: Int) -> PageText? {
        lock.withLock { pages[page] }
    }

    /// Extracts on first use; a page that fails to extract counts as empty.
    public func text(_ page: Int) -> PageText {
        if let text = cached(page) { return text }
        let text = (try? engine.text(onPage: page)) ?? .empty
        lock.withLock { pages[page] = text }
        return text
    }
}
