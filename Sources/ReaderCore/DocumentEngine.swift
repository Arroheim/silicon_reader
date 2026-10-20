import CoreGraphics
import Foundation

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case unsupportedFormat(URL)
    case openFailed(URL, reason: String)
    case passwordRequired(URL)
    case wrongPassword(URL)
    case invalidPage(Int)
    case renderFailed(page: Int)
    case textExtractionFailed(page: Int)

    public var description: String {
        switch self {
        case .unsupportedFormat(let url): "Unsupported file format: \(url.lastPathComponent)"
        case .openFailed(let url, let reason): "Cannot open \(url.lastPathComponent): \(reason)"
        case .passwordRequired(let url): "\(url.lastPathComponent) is password protected"
        case .wrongPassword(let url): "Wrong password for \(url.lastPathComponent)"
        case .invalidPage(let page): "Page \(page) is out of range"
        case .renderFailed(let page): "Failed to render page \(page)"
        case .textExtractionFailed(let page): "Failed to extract text from page \(page)"
        }
    }
}

/// A format-specific document backend.
///
/// Page indices are 0-based. Geometry is in points (1/72 inch), top-left
/// origin, with the page's intrinsic rotation already applied.
/// Implementations must be safe to call from any thread.
public protocol DocumentEngine: AnyObject, Sendable {
    var url: URL { get }
    var pageCount: Int { get }
    var metadata: DocumentMetadata { get }

    func pageSize(at index: Int) throws -> CGSize

    /// The label printed on the page ("iv", "A-3") when it differs from its number.
    func pageLabel(at index: Int) -> String?

    /// Renders a page so that one point maps to `scale` pixels.
    ///
    /// Engines that can only render at discrete resolutions (DjVu) return the
    /// closest image that is not smaller than requested; callers draw the
    /// result into the target rect rather than relying on its exact size.
    func render(page index: Int, scale: CGFloat) throws -> CGImage

    /// Table of contents; empty when the document has none.
    func outline() -> [OutlineItem]

    func links(onPage index: Int) throws -> [PageLink]

    func text(onPage index: Int) throws -> PageText
}

extension DocumentEngine {
    func checkPage(_ index: Int) throws {
        guard (0..<pageCount).contains(index) else { throw EngineError.invalidPage(index) }
    }
}
