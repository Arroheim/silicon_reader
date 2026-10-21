import CoreGraphics
import Foundation
import ReaderCore

/// Result of checking one document, printed by the child process as one JSON line.
struct FileCheckResult: Codable {
    enum Status: String, Codable {
        case ok
        /// Opened, but something about it looks wrong (see `warnings`).
        case warning
        /// Encrypted; nothing to check without the password.
        case password
        case failed
        /// Set by the parent: the child died (signal) or ran past the timeout.
        case crashed
        case timeout
    }

    var path: String
    var status: Status
    var error: String?
    var warnings: [String] = []
    var format: String?
    var pages: Int = 0
    var outlineItems: Int = 0
    var textChars: Int = 0
    var links: Int = 0
    var openMs: Double = 0
    /// Slowest of the sampled page renders.
    var slowestRenderMs: Double = 0
    var totalMs: Double = 0
    var maxRSSMB: Double = 0
    var fileSizeMB: Double = 0
}

/// Opens a document and exercises what the reader does when showing it.
enum FileCheck {
    /// Scale for the sampled renders: a typical on-screen zoom on a Retina display.
    static let renderScale: CGFloat = 1.5

    /// Scale for `allPages`: enough to decode every page fully, cheap enough for whole libraries.
    static let sweepScale: CGFloat = 0.3

    /// `allPages` also renders every page at `sweepScale`, which catches
    /// failures confined to some pages (e.g. a shared DjVu dictionary).
    static func run(_ url: URL, allPages: Bool = false) -> FileCheckResult {
        let start = Date()
        var result = FileCheckResult(path: url.path, status: .ok)
        result.fileSizeMB = Double((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_048_576
        check(url, allPages: allPages, into: &result)
        result.totalMs = Date().timeIntervalSince(start) * 1000
        result.maxRSSMB = maxRSSMegabytes()
        return result
    }

    private static func check(_ url: URL, allPages: Bool, into result: inout FileCheckResult) {
        let engine: any DocumentEngine
        do {
            let opened = Date()
            engine = try DocumentOpener.open(url)
            result.openMs = Date().timeIntervalSince(opened) * 1000
        } catch EngineError.passwordRequired(_) {
            result.status = .password
            return
        } catch {
            result.status = .failed
            result.error = String(describing: error)
            return
        }

        result.format = engine.metadata.format
        result.pages = engine.pageCount
        result.outlineItems = countOutline(engine.outline())

        // First, middle and last page: where broken files usually show up.
        let samples = Array(Set([0, engine.pageCount / 2, engine.pageCount - 1])).sorted()
        for page in samples {
            do {
                let size = try engine.pageSize(at: page)
                if size.width < 10 || size.height < 10 || size.width > 20_000 || size.height > 20_000 {
                    result.warnings.append("page \(page + 1): odd size \(Int(size.width))×\(Int(size.height)) pt")
                }
                let rendered = Date()
                let image = try engine.render(page: page, scale: renderScale)
                result.slowestRenderMs = max(result.slowestRenderMs, Date().timeIntervalSince(rendered) * 1000)
                if image.width < 2 || image.height < 2 {
                    result.warnings.append("page \(page + 1): empty render")
                }
                result.textChars += try engine.text(onPage: page).scalars.count
                result.links += try engine.links(onPage: page).count
            } catch {
                result.status = .failed
                result.error = "page \(page + 1): \(error)"
                return
            }
        }

        if allPages {
            var failedPages: [Int] = []
            for page in 0..<engine.pageCount where (try? engine.render(page: page, scale: sweepScale)) == nil {
                failedPages.append(page + 1)
            }
            if !failedPages.isEmpty {
                result.status = .failed
                let shown = failedPages.prefix(10).map(String.init).joined(separator: ", ")
                result.error = "\(failedPages.count) pages fail to render: \(shown)\(failedPages.count > 10 ? "…" : "")"
                return
            }
        }

        if DocumentFormat.detect(url) == .pdf, let reference = coreGraphicsPageCount(url),
            reference != engine.pageCount
        {
            result.warnings.append("page count \(engine.pageCount), Core Graphics says \(reference)")
        }
        if !result.warnings.isEmpty { result.status = .warning }
    }

    private static func countOutline(_ items: [OutlineItem]) -> Int {
        items.reduce(0) { $0 + 1 + countOutline($1.children) }
    }

    private static func coreGraphicsPageCount(_ url: URL) -> Int? {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted else { return nil }
        return document.numberOfPages
    }

    private static func maxRSSMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576  // bytes on macOS
    }
}
