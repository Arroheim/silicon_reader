import CoreGraphics
import Foundation

/// What an annotation looks like to the reader; SumatraPDF's colors come with
/// each kind (yellow highlight, green underline, red strike-out and ink).
public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
    case highlight, underline, strikeOut, note, freehand
    /// Anything else the file already contains: shown and removable, not editable.
    case other

    /// Whether the kind marks up text rather than a spot on the page.
    public var isTextMarkup: Bool {
        self == .highlight || self == .underline || self == .strikeOut
    }
}

/// An annotation on a page. `index` identifies it until the page changes.
public struct PageAnnotation: Equatable, Sendable {
    public var index: Int
    public var kind: AnnotationKind
    /// Bounds in page points.
    public var rect: CGRect
    public var contents: String

    public init(index: Int, kind: AnnotationKind, rect: CGRect, contents: String = "") {
        self.index = index
        self.kind = kind
        self.rect = rect
        self.contents = contents
    }
}
