import CoreGraphics
import Foundation

public struct TextMatch: Sendable, Equatable {
    public var page: Int
    /// Scalar range within the page's `PageText`.
    public var range: Range<Int>
    /// Highlight boxes in page points, one per visual line.
    public var rects: [CGRect]
}

/// Plain-text search over a page's text layer.
///
/// Any run of whitespace in the query matches any run of whitespace (spaces,
/// line breaks) in the text, so phrases are found across line wraps.
public enum TextSearch {
    public static func matches(
        of query: String, in text: PageText, page: Int, caseSensitive: Bool = false
    ) -> [TextMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = normalize(Array(trimmed.unicodeScalars), caseSensitive: caseSensitive).scalars
        guard !pattern.isEmpty else { return [] }

        let (haystack, origin) = normalize(text.scalars, caseSensitive: caseSensitive)
        var result: [TextMatch] = []
        var i = 0
        while i + pattern.count <= haystack.count {
            if haystack[i..<(i + pattern.count)].elementsEqual(pattern) {
                let range = origin[i]..<(origin[i + pattern.count - 1] + 1)
                result.append(TextMatch(page: page, range: range, rects: text.rects(for: range)))
                i += pattern.count
            } else {
                i += 1
            }
        }
        return result
    }

    /// Case-folds scalars and collapses whitespace runs to a single space,
    /// returning for each output scalar the index of its source scalar.
    static func normalize(
        _ scalars: [Unicode.Scalar], caseSensitive: Bool
    ) -> (scalars: [Unicode.Scalar], origin: [Int]) {
        var out: [Unicode.Scalar] = []
        var origin: [Int] = []
        out.reserveCapacity(scalars.count)
        origin.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() {
            if scalar.properties.isWhitespace {
                if out.last != " " {
                    out.append(" ")
                    origin.append(index)
                }
                continue
            }
            out.append(caseSensitive ? scalar : fold(scalar))
            origin.append(index)
        }
        return (out, origin)
    }

    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let lower = scalar.properties.lowercaseMapping.unicodeScalars
        return lower.count == 1 ? lower.first! : scalar
    }
}
