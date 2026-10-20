import CoreGraphics
import Foundation

/// Target of a link or outline entry. Points are in page space (top-left origin).
public enum Destination: Sendable, Hashable {
    case page(Int, point: CGPoint? = nil)
    case uri(String)
}

public struct OutlineItem: Sendable, Hashable {
    public var title: String
    public var destination: Destination?
    public var isExpanded: Bool
    public var children: [OutlineItem]

    public init(title: String, destination: Destination?, isExpanded: Bool = false, children: [OutlineItem] = []) {
        self.title = title
        self.destination = destination
        self.isExpanded = isExpanded
        self.children = children
    }
}

public struct PageLink: Sendable, Hashable {
    /// In page points, top-left origin.
    public var rect: CGRect
    public var destination: Destination

    public init(rect: CGRect, destination: Destination) {
        self.rect = rect
        self.destination = destination
    }
}

/// Document information shown in the properties dialog. Values are as stored
/// in the file; absent fields are nil.
public struct DocumentMetadata: Sendable, Hashable {
    public var format: String?
    public var title: String?
    public var author: String?
    public var subject: String?
    public var keywords: String?
    public var creator: String?
    public var producer: String?
    public var creationDate: Date?
    public var modificationDate: Date?
    public var encryption: String?

    public init(format: String? = nil) {
        self.format = format
    }
}

/// The text layer of one page: a flat sequence of Unicode scalars, each with
/// its bounding box in page points (top-left origin).
///
/// Separators synthesized between words and lines (" " and "\n") have a null
/// rect. `lines[i]` identifies the visual line of scalar `i`, which search and
/// selection use to merge per-character boxes into one box per line.
public struct PageText: Sendable, Equatable {
    public private(set) var scalars: [Unicode.Scalar] = []
    public private(set) var rects: [CGRect] = []
    public private(set) var lines: [Int] = []

    public static let empty = PageText()

    public init() {}

    public var isEmpty: Bool { scalars.isEmpty }

    public var string: String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    public func string(in range: Range<Int>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range])
        return String(view)
    }

    public mutating func append(_ scalar: Unicode.Scalar, rect: CGRect, line: Int) {
        scalars.append(scalar)
        rects.append(rect)
        lines.append(line)
    }

    /// Appends a synthesized separator unless the text already ends with
    /// whitespace. A line break supersedes a synthesized word space.
    public mutating func appendSeparator(_ separator: Unicode.Scalar) {
        guard let last = scalars.last else { return }
        if !last.properties.isWhitespace {
            append(separator, rect: .null, line: lines[lines.count - 1])
        } else if separator == "\n", last == " ", rects[rects.count - 1].isNull {
            scalars[scalars.count - 1] = "\n"
        }
    }

    /// Bounding boxes for a scalar range, merged into one rect per visual line.
    public func rects(for range: Range<Int>) -> [CGRect] {
        var result: [CGRect] = []
        var currentLine: Int?
        for i in range where !rects[i].isNull {
            if lines[i] == currentLine, let last = result.popLast() {
                result.append(last.union(rects[i]))
            } else {
                result.append(rects[i])
                currentLine = lines[i]
            }
        }
        return result
    }
}
