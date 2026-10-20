/// Parsing and matching for the command palette (SumatraPDF's Ctrl+K).
public struct PaletteQuery: Equatable, Sendable {
    /// Which list the palette shows; chosen by the first character as in Sumatra.
    public enum Source: Character, CaseIterable, Sendable {
        case commands = ">"
        case tabs = "@"
        case history = "#"
        case favorites = "$"
        case outline = "%"
    }

    /// Nil means everything (commands, tabs and recent files together).
    public var source: Source?
    /// Lowercased search words.
    public var words: [String]

    public init(_ text: String) {
        var rest = Substring(text)
        if let first = rest.first, let source = Source(rawValue: first) {
            self.source = source
            rest = rest.dropFirst()
        } else {
            self.source = nil
        }
        words = rest.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Score for a candidate, or nil if it doesn't match: every word must occur
    /// in the title (or the detail line); matches at word starts and in the
    /// title rank higher. An empty query matches everything with score 0.
    public func score(title: String, detail: String = "") -> Int? {
        guard !words.isEmpty else { return 0 }
        let title = title.lowercased()
        let detail = detail.lowercased()
        var total = 0
        for word in words {
            if let range = title.range(of: word) {
                let atStart = range.lowerBound == title.startIndex
                let atWordStart = atStart || !title[title.index(before: range.lowerBound)].isLetter
                total += atWordStart ? 3 : 2
                if atStart { total += 1 }
            } else if detail.contains(word) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    /// Items that match, best first; ties keep their original order.
    public func filter<T>(_ items: [T], title: (T) -> String, detail: (T) -> String = { _ in "" }) -> [T] {
        items.enumerated()
            .compactMap { offset, item in score(title: title(item), detail: detail(item)).map { (item, $0, offset) } }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .map(\.0)
    }
}
