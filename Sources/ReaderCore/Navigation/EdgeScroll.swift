import CoreGraphics

/// Scrolling while a selection is dragged to the edge of the viewport, for
/// selecting more text than fits on screen. A window near the screen's edge
/// leaves the pointer no room to go past it, so the zone starts inside, and
/// `pull` counts the mouse movement that the screen's edge swallowed.
public enum EdgeScroll {
    /// Depth of the band along each edge where scrolling starts, in points.
    public static let zone: CGFloat = 96
    /// Scroll per tick for a depth `d` is `d * linear + d² * quadratic`, quick
    /// once the mouse is pulled hard, plus `startBoost` where the band starts,
    /// fading out by `boostDepth`, so entering the band already moves the page.
    /// A bigger boost than `boostDepth * linear` would make going deeper slower.
    private static let linear: CGFloat = 1.0 / 24
    private static let quadratic: CGFloat = 1.0 / 1200
    private static let startBoost: CGFloat = 1.5
    private static let boostDepth: CGFloat = 48
    private static let maxStep: CGFloat = 60
    private static let maxPull: CGFloat = 300

    /// How deep `value` is in a band: negative at the low edge, positive at the
    /// high edge, zero between them.
    private static func depth(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        value < low + zone ? value - (low + zone) : (value > high - zone ? value - (high - zone) : 0)
    }

    /// How far to scroll in one tick for a pointer at `point`: zero outside the
    /// bands, growing the closer the pointer gets to the edge, past it, or the
    /// more `pull` has built up.
    public static func delta(for point: CGPoint, in viewport: CGRect, pull: CGPoint = .zero) -> CGPoint {
        func step(_ depth: CGFloat, _ pull: CGFloat) -> CGFloat {
            guard depth != 0 else { return 0 }
            let total = abs(depth) + pull
            let boost = startBoost * max(0, 1 - total / boostDepth)
            return (depth < 0 ? -1 : 1) * min(maxStep, total * linear + total * total * quadratic + boost)
        }
        return CGPoint(
            x: step(depth(point.x, viewport.minX, viewport.maxX), pull.x),
            y: step(depth(point.y, viewport.minY, viewport.maxY), pull.y))
    }

    /// The pull after a mouse event, with the pointer now at `point`. `moved` is
    /// what the mouse reported and `travelled` how far the pointer really went,
    /// both in view coordinates. Outward movement that didn't move the pointer
    /// adds to the pull. Moving back fades it in step with the way out of the
    /// band, so it is gone by the band's end and speed never drops at once.
    public static func pull(
        _ pull: CGPoint, at point: CGPoint, in viewport: CGRect, moved: CGPoint, travelled: CGPoint
    ) -> CGPoint {
        func updated(_ pull: CGFloat, depth: CGFloat, moved: CGFloat, travelled: CGFloat) -> CGFloat {
            guard depth != 0 else { return 0 }
            let side: CGFloat = depth < 0 ? -1 : 1
            let outward = moved * side
            if outward > 0 { return min(maxPull, pull + max(0, outward - travelled * side)) }
            return pull * abs(depth) / (abs(depth) - outward)
        }
        return CGPoint(
            x: updated(
                pull.x, depth: depth(point.x, viewport.minX, viewport.maxX), moved: moved.x, travelled: travelled.x),
            y: updated(
                pull.y, depth: depth(point.y, viewport.minY, viewport.maxY), moved: moved.y, travelled: travelled.y))
    }
}
