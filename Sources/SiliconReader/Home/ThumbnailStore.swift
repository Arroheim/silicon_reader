import AppKit
import CryptoKit
import ReaderCore

/// First-page thumbnails for the home page, cached as PNG files.
@MainActor
final class ThumbnailStore {
    /// SumatraPDF's thumbnail width, in points.
    static let width: CGFloat = 212

    let directory: URL
    private var memory: [String: NSImage] = [:]
    private var pending = 0

    /// No thumbnail is being rendered (debug snapshot hook waits for this).
    var isIdle: Bool { pending == 0 }

    init(directory: URL) {
        self.directory = directory
    }

    private func fileURL(for path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest.prefix(32)).png")
    }

    func thumbnail(for path: String) -> NSImage? {
        if let cached = memory[path] { return cached }
        guard let image = NSImage(contentsOf: fileURL(for: path)) else { return nil }
        memory[path] = image
        return image
    }

    /// Renders page 1 in the background unless a thumbnail newer than the file exists.
    func ensureThumbnail(for engine: any DocumentEngine) {
        let path = engine.url.path
        let target = fileURL(for: path)
        let fileDate = (try? engine.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let thumbDate = (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let thumbDate, let fileDate, thumbDate >= fileDate { return }

        let directory = directory
        let pixelWidth = Self.width * 2
        pending += 1
        Task.detached(priority: .utility) {
            defer { Task { @MainActor in self.finished(path) } }
            guard let size = try? engine.pageSize(at: 0), size.width > 0,
                let image = try? engine.render(page: 0, scale: pixelWidth / size.width)
            else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: target, options: .atomic)
        }
    }

    private func finished(_ path: String) {
        memory[path] = nil
        pending -= 1
    }
}
