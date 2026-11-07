import CoreGraphics
import Testing

@testable import ReaderCore

@Suite("Edge scroll")
struct EdgeScrollTests {
    private static let viewport = CGRect(x: 100, y: 1000, width: 400, height: 300)
    /// On the bottom edge, where a window at the screen's edge pins the pointer.
    private static let pinned = CGPoint(x: 300, y: 1300)

    private func step(_ point: CGPoint, pull: CGFloat = 0) -> CGPoint {
        EdgeScroll.delta(for: point, in: Self.viewport, pull: CGPoint(x: 0, y: pull))
    }

    /// Regression: selecting text moved the page while the pointer was mid-window.
    @Test(
        "nothing moves away from the edges",
        arguments: [CGPoint(x: 300, y: 1150), CGPoint(x: 200, y: 1100), CGPoint(x: 400, y: 1200)])
    func middle(point: CGPoint) {
        #expect(step(point) == .zero)
        #expect(step(point, pull: 100) == .zero, "a leftover pull doesn't count mid-window")
    }

    @Test("scrolls toward each edge")
    func direction() {
        #expect(step(CGPoint(x: 300, y: 1000)).y < 0)
        #expect(step(CGPoint(x: 300, y: 1300)).y > 0)
        #expect(step(CGPoint(x: 100, y: 1150)).x < 0)
        #expect(step(CGPoint(x: 500, y: 1150)).x > 0)
    }

    @Test("speeds up the further the pointer goes, more than in proportion")
    func acceleration() {
        let speeds = [1288, 1300, 1340, 1400].map { step(CGPoint(x: 300, y: CGFloat($0))).y }
        #expect(speeds == speeds.sorted())
        #expect(speeds[0] > 0)
        #expect(speeds[3] > speeds[1] * 3, "\(speeds)")
    }

    @Test("entering the band already moves the page, and deeper is never slower")
    func startOfBand() {
        #expect(step(CGPoint(x: 300, y: 1205)).y >= 1.4)
        let speeds = stride(from: 1205, through: 1300, by: 5).map { step(CGPoint(x: 300, y: CGFloat($0))).y }
        #expect(speeds == speeds.sorted())
    }

    @Test("the boost is gone halfway into the band")
    func boostFades() {
        let halfway = step(CGPoint(x: 300, y: 1252)).y
        #expect(abs(halfway - (48.0 / 24 + 48.0 * 48 / 1200)) < 0.001)
    }

    @Test("a pull speeds up a pointer stuck on the edge")
    func pullSpeedsUp() {
        #expect(step(Self.pinned, pull: 80).y > step(Self.pinned).y * 2)
    }

    @Test("a pointer far outside doesn't race")
    func capped() {
        #expect(step(CGPoint(x: 300, y: 9000)).y == 60)
        #expect(step(CGPoint(x: 300, y: -9000)).y == -60)
    }

    private func pull(
        _ pull: CGFloat = 0, at point: CGPoint = pinned, moved: CGFloat, travelled: CGFloat
    ) -> CGFloat {
        EdgeScroll.pull(
            CGPoint(x: 0, y: pull), at: point, in: Self.viewport, moved: CGPoint(x: 0, y: moved),
            travelled: CGPoint(x: 0, y: travelled)
        ).y
    }

    @Test("what the screen's edge swallows builds up the pull")
    func swallowedMovement() {
        #expect(pull(moved: 10, travelled: 0) == 10)
        #expect(pull(10, moved: 5, travelled: 0) == 15)
        #expect(pull(moved: 10, travelled: 4) == 6, "stopped partway")
    }

    @Test("a pointer that is free to move adds no pull")
    func freePointer() {
        #expect(pull(moved: 10, travelled: 10) == 0)
    }

    @Test("moving back fades the pull in step with the way out of the band")
    func release() {
        // From 96 deep to 48: half the way out, half the pull.
        #expect(pull(100, at: CGPoint(x: 300, y: 1252), moved: -48, travelled: -48) == 50)
        #expect(pull(100, moved: 0, travelled: 0) == 100, "holding still keeps it")
        #expect(pull(30, at: CGPoint(x: 300, y: 1150), moved: -10, travelled: -10) == 0, "out of the band")
    }

    /// Regression: leaving a narrow band dropped the speed from full to nothing.
    @Test("backing out step by step slows down gradually, with no sudden drop")
    func gradualRelease() {
        var current: CGFloat = 200
        var speed = step(Self.pinned, pull: current).y
        var y = Self.pinned.y
        while y > 1206 {
            y -= 2
            let point = CGPoint(x: 300, y: y)
            current = pull(current, at: point, moved: -2, travelled: -2)
            let next = step(point, pull: current).y
            #expect(next <= speed)
            #expect(speed - next < 6, "at y \(y): \(speed) to \(next), over 10% of top speed at once")
            speed = next
        }
    }

    @Test("the pull has a limit, so stopping doesn't take forever")
    func pullLimit() {
        #expect(pull(290, moved: 100, travelled: 0) == 300)
    }

    @Test("works the same at the top edge")
    func topEdge() {
        let top = CGPoint(x: 300, y: 1000)
        #expect(pull(at: top, moved: -10, travelled: 0) == 10)
        #expect(pull(10, at: top, moved: 5, travelled: 5) < 10)
    }
}
