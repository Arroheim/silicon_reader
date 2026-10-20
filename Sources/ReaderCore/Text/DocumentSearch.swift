/// Finding the next match across a whole document, like SumatraPDF's F3.
public enum DocumentSearch {
    /// The first match starting at or after `position` (going forward) or
    /// starting before it (going back), walking pages from there and wrapping
    /// around the document once. To step from a current match, pass its
    /// `lowerBound + 1` forward or its `lowerBound` backward.
    ///
    /// `text` supplies each page's text layer (may be slow; called lazily),
    /// `progress` is told each page as it is searched and `isCancelled` is
    /// polled between pages.
    public static func next(
        _ query: String, caseSensitive: Bool, after position: TextPosition, forward: Bool, pageCount: Int,
        text: (Int) -> PageText, progress: (Int) -> Void = { _ in }, isCancelled: () -> Bool = { false }
    ) -> TextMatch? {
        guard pageCount > 0 else { return nil }
        let startPage = min(max(position.page, 0), pageCount - 1)

        func matches(on page: Int) -> [TextMatch] {
            TextSearch.matches(of: query, in: text(page), page: page, caseSensitive: caseSensitive)
        }

        // The starting page is visited twice: the part after the position
        // first, then (after wrapping) the part before it.
        for step in 0...pageCount {
            if isCancelled() { return nil }
            let offset = forward ? step : -step
            let page = ((startPage + offset) % pageCount + pageCount) % pageCount
            progress(page)
            let found = matches(on: page)
            let candidate: TextMatch?
            switch step {
            case 0:
                candidate =
                    forward
                    ? found.first { $0.range.lowerBound >= position.index }
                    : found.last { $0.range.lowerBound < position.index }
            case pageCount:
                candidate =
                    forward
                    ? found.first { $0.range.lowerBound < position.index }
                    : found.last { $0.range.lowerBound >= position.index }
            default:
                candidate = forward ? found.first : found.last
            }
            if let candidate { return candidate }
        }
        return nil
    }
}
