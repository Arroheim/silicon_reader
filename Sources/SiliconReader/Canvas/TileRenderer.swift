import CoreGraphics
import OSLog
import ReaderCore

/// Identifies a rendered piece of a page.
///
/// Tiles live in unrotated page space at a given render scale (device pixels
/// per page point); rotation is applied when drawing. `column`/`row` are nil
/// for a whole-page image (DjVu, previews).
struct TileKey: Hashable {
    let page: Int
    /// Render scale rounded to 1/1000 so equal zooms share tiles.
    let scaleKey: Int
    let column: Int?
    let row: Int?

    static let size: CGFloat = 512

    init(page: Int, scale: CGFloat, column: Int? = nil, row: Int? = nil) {
        self.page = page
        self.scaleKey = Int((scale * 1000).rounded())
        self.column = column
        self.row = row
    }

    var scale: CGFloat { CGFloat(scaleKey) / 1000 }

    /// The page area (points) this tile covers, or nil for the whole page.
    var region: CGRect? {
        guard let column, let row else { return nil }
        let side = Self.size / scale
        return CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)
    }
}

/// Renders tiles off the main thread with a bounded number of workers and an
/// LRU memory budget. Requests not re-requested by the latest draw pass are
/// dropped before they start, so zooming never renders stale resolutions.
@MainActor
final class TileRenderer {
    private struct Entry {
        let image: CGImage
        var lastUsed: UInt64
        var cost: Int { image.bytesPerRow * image.height }
    }

    private let engine: any DocumentEngine
    private let maxConcurrent: Int
    private let memoryBudget: Int
    private var cache: [TileKey: Entry] = [:]
    private var cacheBytes = 0
    private var clock: UInt64 = 0
    private var pending: [TileKey] = []
    private var running: Set<TileKey> = []
    private var failed: Set<TileKey> = []

    /// Called on the main actor when a tile becomes available.
    var onTileReady: ((TileKey) -> Void)?

    init(engine: any DocumentEngine, maxConcurrent: Int = 2, memoryBudget: Int = 384 << 20) {
        self.engine = engine
        self.maxConcurrent = maxConcurrent
        self.memoryBudget = memoryBudget
    }

    var isIdle: Bool { pending.isEmpty && running.isEmpty }

    /// Whether `key` is cached, without touching its LRU position.
    func hasImage(for key: TileKey) -> Bool {
        cache[key] != nil
    }

    func image(for key: TileKey) -> CGImage? {
        guard var entry = cache[key] else { return nil }
        clock += 1
        entry.lastUsed = clock
        cache[key] = entry
        return entry.image
    }

    /// Replaces the wanted set with `keys` (highest priority first).
    func request(_ keys: [TileKey]) {
        pending = keys.filter { cache[$0] == nil && !running.contains($0) && !failed.contains($0) }
        pump()
    }

    /// The best cached image of a whole page at any scale, for drawing while
    /// the right tiles are still rendering.
    func anyWholePageImage(for page: Int) -> CGImage? {
        cache.filter { $0.key.page == page && $0.key.column == nil }
            .max { $0.key.scaleKey < $1.key.scaleKey }?.value.image
    }

    private func pump() {
        while running.count < maxConcurrent, !pending.isEmpty {
            let key = pending.removeFirst()
            running.insert(key)
            let engine = engine
            Task.detached(priority: .userInitiated) {
                let result = Result { try engine.render(page: key.page, scale: key.scale, region: key.region) }
                await self.finish(key, result: result)
            }
        }
    }

    var failedCount: Int { failed.count }

    private func finish(_ key: TileKey, result: Result<CGImage, any Error>) {
        running.remove(key)
        switch result {
        case .success(let image):
            clock += 1
            let entry = Entry(image: image, lastUsed: clock)
            cache[key] = entry
            cacheBytes += entry.cost
            evict()
            onTileReady?(key)
        case .failure(let error):
            let tile = key.column.map { "\($0),\(key.row ?? 0)" } ?? "whole page"
            Self.log.error(
                "render failed: page \(key.page) scale \(key.scale) tile \(tile): \(String(describing: error), privacy: .public)"
            )
            failed.insert(key)
        }
        pump()
    }

    private static let log = Logger(subsystem: "io.github.arroheim.siliconreader", category: "render")

    private func evict() {
        guard cacheBytes > memoryBudget else { return }
        for (key, entry) in cache.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            guard cacheBytes > memoryBudget * 3 / 4 else { break }
            cache[key] = nil
            cacheBytes -= entry.cost
        }
    }
}
