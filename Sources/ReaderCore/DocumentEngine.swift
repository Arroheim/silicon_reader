import CoreGraphics
import Foundation

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case unsupportedFormat(URL)
    case openFailed(URL, reason: String)
    case invalidPage(Int)
    case renderFailed(page: Int)

    public var description: String {
        switch self {
        case .unsupportedFormat(let url): "Unsupported file format: \(url.lastPathComponent)"
        case .openFailed(let url, let reason): "Cannot open \(url.lastPathComponent): \(reason)"
        case .invalidPage(let page): "Page \(page) is out of range"
        case .renderFailed(let page): "Failed to render page \(page)"
        }
    }
}

/// A format-specific document backend.
///
/// Page indices are 0-based. Sizes are in points (1/72 inch) with the page's
/// intrinsic rotation already applied. Implementations must be safe to call
/// from any thread.
public protocol DocumentEngine: AnyObject, Sendable {
    var url: URL { get }
    var pageCount: Int { get }

    func pageSize(at index: Int) throws -> CGSize

    /// Renders a page so that one point maps to `scale` pixels.
    ///
    /// Engines that can only render at discrete resolutions (DjVu) return the
    /// closest image that is not smaller than requested; callers draw the
    /// result into the target rect rather than relying on its exact size.
    func render(page index: Int, scale: CGFloat) throws -> CGImage
}

extension DocumentEngine {
    func checkPage(_ index: Int) throws {
        guard (0..<pageCount).contains(index) else { throw EngineError.invalidPage(index) }
    }
}
