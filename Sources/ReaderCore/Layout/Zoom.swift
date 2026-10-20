import CoreGraphics

/// A "virtual" zoom as in SumatraPDF: either an absolute percentage (100 =
/// one PDF point per screen point) or a fit mode whose real value depends on
/// the viewport.
public enum Zoom: Hashable, Sendable {
    case fitPage
    case fitWidth
    case fitHeight
    case fitContent
    /// Fit page, but never above 100%.
    case shrinkToFit
    case percent(CGFloat)

    public static let actualSize = Zoom.percent(100)
    public static let minPercent: CGFloat = 8.33
    public static let maxPercent: CGFloat = 6400

    /// SumatraPDF's default zoom levels (Adobe Reader's plus four in-between steps).
    public static let levels: [CGFloat] = [
        8.33, 12.5, 18, 25, 33.33, 50, 66.67, 75,
        100, 125, 150, 200, 300, 400, 600, 800, 1000,
        1200, 1600, 2000, 2400, 3200, 4800, 6400,
    ]

    /// The order the "toggle zoom" command (Z) cycles through.
    static let toggleCycle: [Zoom] = [.fitPage, .fitWidth, .fitHeight, .fitContent, .shrinkToFit]

    public var isFit: Bool {
        if case .percent = self { false } else { true }
    }

    public static func clamped(_ percent: CGFloat) -> Zoom {
        .percent(min(max(percent, minPercent), maxPercent))
    }

    /// Next zoom for the Z command; any absolute zoom goes back to fit page.
    public var toggled: Zoom {
        guard let i = Self.toggleCycle.firstIndex(of: self) else { return .fitPage }
        return Self.toggleCycle[(i + 1) % Self.toggleCycle.count]
    }

    /// One step of zoom in/out, mirroring SumatraPDF's GetNextZoomStep: walk the
    /// level table from the current real zoom, but stop at fit page / fit width
    /// when they fall between the current zoom and the next level.
    ///
    /// All values are percentages; `fitPage` and `fitWidth` are the real
    /// percentages those modes currently produce.
    public static func step(
        from current: CGFloat, zoomIn: Bool, fitPage: CGFloat, fitWidth: CGFloat
    ) -> Zoom {
        let fuzz: CGFloat = 0.01
        if zoomIn {
            guard current + fuzz < maxPercent else { return .percent(maxPercent) }
            let next = levels.first { $0 - fuzz > current } ?? maxPercent
            if current + fuzz < fitPage && fitPage < next - fuzz { return .fitPage }
            if current + fuzz < fitWidth && fitWidth < next - fuzz { return .fitWidth }
            return .percent(next)
        } else {
            guard current - fuzz > minPercent else { return .percent(minPercent) }
            let next = levels.last { $0 + fuzz < current } ?? minPercent
            if next + fuzz < fitWidth && fitWidth < current - fuzz && fitWidth != fitPage { return .fitWidth }
            if next + fuzz < fitPage && fitPage < current - fuzz { return .fitPage }
            return .percent(next)
        }
    }
}
