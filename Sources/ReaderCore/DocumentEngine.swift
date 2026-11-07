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
    case annotationFailed(page: Int)
    case saveFailed(URL, reason: String)

    public var description: String {
        switch self {
        case .unsupportedFormat(let url): "Unsupported file format: \(url.lastPathComponent)"
        case .openFailed(let url, let reason): "Cannot open \(url.lastPathComponent): \(reason)"
        case .passwordRequired(let url): "\(url.lastPathComponent) is password protected"
        case .wrongPassword(let url): "Wrong password for \(url.lastPathComponent)"
        case .invalidPage(let page): "Page \(page) is out of range"
        case .renderFailed(let page): "Failed to render page \(page)"
        case .textExtractionFailed(let page): "Failed to extract text from page \(page)"
        case .annotationFailed(let page): "Failed to change annotations on page \(page)"
        case .saveFailed(let url, let reason): "Cannot save \(url.lastPathComponent): \(reason)"
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
    /// `region` (page points) limits the output to part of the page when
    /// `supportsRegionRendering` is true; other engines always return the
    /// whole page. Engines that can only render at discrete resolutions (DjVu)
    /// return the closest image that is not smaller than requested; callers
    /// draw the result into the target rect rather than relying on its size.
    func render(page index: Int, scale: CGFloat, region: CGRect?) throws -> CGImage

    /// Whether `render` honors `region`, so callers can render in tiles.
    var supportsRegionRendering: Bool { get }

    /// Bounding box of the page's visible content (page points), for fit
    /// content zoom. Nil when unknown; callers then use the whole page.
    func contentBox(at index: Int) -> CGRect?

    /// Table of contents; empty when the document has none.
    func outline() -> [OutlineItem]

    func links(onPage index: Int) throws -> [PageLink]

    func text(onPage index: Int) throws -> PageText

    /// Whether this document can be annotated; the rest of the annotation
    /// API is only called when it can. Defaults to false.
    var supportsAnnotations: Bool { get }

    /// Annotations made since the document was opened or saved over itself.
    var hasUnsavedChanges: Bool { get }

    func annotations(onPage index: Int) throws -> [PageAnnotation]

    /// Marks up the text under `rects`, one per line. `kind` must be text markup.
    @discardableResult
    func addMarkup(_ kind: AnnotationKind, rects: [CGRect], onPage index: Int) throws -> Int

    @discardableResult
    func addNote(_ text: String, at point: CGPoint, onPage index: Int) throws -> Int

    /// Adds one freehand annotation; each stroke is a run of connected points.
    @discardableResult
    func addFreehand(strokes: [[CGPoint]], onPage index: Int) throws -> Int

    func setContents(_ text: String, ofAnnotation annotation: Int, onPage index: Int) throws

    func removeAnnotation(_ annotation: Int, onPage index: Int) throws

    /// Writes the document with its annotations to `url`, atomically, so
    /// `url` may be the open file itself.
    func save(to url: URL) throws
}

extension DocumentEngine {
    public var supportsAnnotations: Bool { false }
    public var hasUnsavedChanges: Bool { false }
    public func annotations(onPage index: Int) throws -> [PageAnnotation] { [] }

    public func addMarkup(_ kind: AnnotationKind, rects: [CGRect], onPage index: Int) throws -> Int {
        throw EngineError.annotationFailed(page: index)
    }

    public func addNote(_ text: String, at point: CGPoint, onPage index: Int) throws -> Int {
        throw EngineError.annotationFailed(page: index)
    }

    public func addFreehand(strokes: [[CGPoint]], onPage index: Int) throws -> Int {
        throw EngineError.annotationFailed(page: index)
    }

    public func setContents(_ text: String, ofAnnotation annotation: Int, onPage index: Int) throws {
        throw EngineError.annotationFailed(page: index)
    }

    public func removeAnnotation(_ annotation: Int, onPage index: Int) throws {
        throw EngineError.annotationFailed(page: index)
    }

    public func save(to url: URL) throws {
        throw EngineError.saveFailed(url, reason: "this format can't be saved")
    }

    public func render(page index: Int, scale: CGFloat) throws -> CGImage {
        try render(page: index, scale: scale, region: nil)
    }

    func checkPage(_ index: Int) throws {
        guard (0..<pageCount).contains(index) else { throw EngineError.invalidPage(index) }
    }
}
