import AppKit

/// Scroll view for `DocumentView` that adds SumatraPDF's wheel behaviors:
/// ⌘-scroll zooms, and scrolling past the edge of a non-continuous page turns it.
@MainActor
final class CanvasScrollView: NSScrollView {
    /// Accumulated trackpad delta before ⌘-scroll counts as one zoom step.
    private static let zoomThreshold: CGFloat = 24
    private var zoomAccumulator: CGFloat = 0
    /// A trackpad gesture turns at most one page; reset when the next gesture begins.
    private var flippedInGesture = false

    private var documentCanvas: DocumentView? { documentView as? DocumentView }

    override func scrollWheel(with event: NSEvent) {
        guard let canvas = documentCanvas else { return super.scrollWheel(with: event) }

        if event.modifierFlags.contains(.command) {
            zoom(with: event, canvas: canvas)
            return
        }

        if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
            flippedInGesture = false
        }
        let isMomentum = event.momentumPhase != []
        if !flippedInGesture && !isMomentum && canvas.flipPageForScroll(deltaY: event.scrollingDeltaY) {
            // Mouse wheels have no phases: every notch is its own "gesture".
            flippedInGesture = event.phase != []
            return
        }
        if flippedInGesture { return }
        super.scrollWheel(with: event)
    }

    private func zoom(with event: NSEvent, canvas: DocumentView) {
        let point = canvas.convert(event.locationInWindow, from: nil)
        let viewportPoint = CGPoint(x: point.x - contentView.bounds.minX, y: point.y - contentView.bounds.minY)
        if !event.hasPreciseScrollingDeltas {
            // Mouse wheel: one notch, one step.
            if event.scrollingDeltaY != 0 { canvas.zoomStep(in: event.scrollingDeltaY > 0, at: viewportPoint) }
            return
        }
        zoomAccumulator += event.scrollingDeltaY
        if abs(zoomAccumulator) >= Self.zoomThreshold {
            canvas.zoomStep(in: zoomAccumulator > 0, at: viewportPoint)
            zoomAccumulator = 0
        }
        if event.phase == .ended { zoomAccumulator = 0 }
    }
}
