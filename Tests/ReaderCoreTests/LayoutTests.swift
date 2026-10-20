import CoreGraphics
import Testing

@testable import ReaderCore

@Suite("Layout")
struct LayoutTests {
    private static let letter = CGSize(width: 600, height: 800)

    private func layout(
        _ sizes: [CGSize], mode: ViewMode = ViewMode(), zoom: Zoom, viewport: CGSize, rotation: Int = 0,
        current: Int = 0, contentBoxes: [CGRect?] = []
    ) -> DocumentLayout {
        LayoutEngine.layout(
            LayoutParams(
                pageSizes: sizes, contentBoxes: contentBoxes, mode: mode, zoom: zoom, rotation: rotation,
                viewport: viewport, currentPage: current))
    }

    @Test(
        "groups pages into rows",
        arguments: [
            (PageArrangement.single, [0...0, 1...1, 2...2, 3...3, 4...4]),
            (.facing, [0...1, 2...3, 4...4]),
            (.book, [0...0, 1...2, 3...4]),
        ])
    func rows(arrangement: PageArrangement, expected: [ClosedRange<Int>]) {
        #expect(LayoutEngine.rows(pageCount: 5, arrangement: arrangement).map(\.pages) == expected)
    }

    @Test("stacks pages with Sumatra's margins and spacing in continuous fit width")
    func continuousFitWidth() {
        let result = layout(
            Array(repeating: Self.letter, count: 3), zoom: .fitWidth, viewport: CGSize(width: 608, height: 400))

        #expect(result.scale == 1)
        #expect(
            result.pageFrames == [
                CGRect(x: 4, y: 2, width: 600, height: 800),
                CGRect(x: 4, y: 806, width: 600, height: 800),
                CGRect(x: 4, y: 1610, width: 600, height: 800),
            ])
        #expect(result.canvasSize == CGSize(width: 608, height: 2412))
    }

    @Test("fit width uses the widest page and centers narrower ones")
    func mixedSizes() {
        let result = layout(
            [Self.letter, CGSize(width: 300, height: 400)], zoom: .fitWidth, viewport: CGSize(width: 608, height: 400))

        #expect(result.scale == 1)
        #expect(result.pageFrames[1] == CGRect(x: 154, y: 806, width: 300, height: 400))
    }

    @Test("single page mode shows only the current page, centered")
    func singlePageFitPage() {
        let result = layout(
            Array(repeating: Self.letter, count: 3), mode: ViewMode(continuous: false), zoom: .fitPage,
            viewport: CGSize(width: 1000, height: 804), current: 1)

        #expect(result.scale == 1)
        #expect(result.pageFrames[0] == nil && result.pageFrames[2] == nil)
        #expect(result.pageFrames[1] == CGRect(x: 200, y: 2, width: 600, height: 800))
        #expect(result.canvasSize == CGSize(width: 1000, height: 804))
    }

    @Test("centers content vertically when it is shorter than the viewport")
    func verticalCentering() {
        let result = layout(
            [CGSize(width: 100, height: 100)], zoom: .actualSize, viewport: CGSize(width: 200, height: 304))

        #expect(result.pageFrames[0] == CGRect(x: 50, y: 102, width: 100, height: 100))
    }

    @Test("facing mode puts pages in two columns")
    func facing() {
        let page = CGSize(width: 100, height: 200)
        let result = layout(
            Array(repeating: page, count: 3), mode: ViewMode(arrangement: .facing), zoom: .actualSize,
            viewport: CGSize(width: 500, height: 300))

        #expect(result.pageFrames[0]?.origin == CGPoint(x: 148, y: 2))
        #expect(result.pageFrames[1]?.origin == CGPoint(x: 252, y: 2))
        #expect(result.pageFrames[2]?.origin == CGPoint(x: 148, y: 206))
    }

    @Test("book view puts the cover alone in the right column")
    func bookContinuous() {
        let page = CGSize(width: 100, height: 200)
        let result = layout(
            Array(repeating: page, count: 3), mode: ViewMode(arrangement: .book), zoom: .actualSize,
            viewport: CGSize(width: 500, height: 300))

        #expect(result.pageFrames[0]?.origin == CGPoint(x: 252, y: 2))
        #expect(result.pageFrames[1]?.origin == CGPoint(x: 148, y: 206))
        #expect(result.pageFrames[2]?.origin == CGPoint(x: 252, y: 206))
    }

    @Test("non-continuous book view shows only the current row")
    func bookPaged() {
        let pages = Array(repeating: CGSize(width: 100, height: 200), count: 5)
        let mode = ViewMode(arrangement: .book, continuous: false)

        let cover = layout(pages, mode: mode, zoom: .actualSize, viewport: CGSize(width: 500, height: 300), current: 0)
        let spread = layout(pages, mode: mode, zoom: .actualSize, viewport: CGSize(width: 500, height: 300), current: 4)

        #expect(cover.pageFrames.map { $0 != nil } == [true, false, false, false, false])
        #expect(spread.pageFrames.map { $0 != nil } == [false, false, false, true, true])
    }

    @Test("fit page in facing mode fits the whole row")
    func facingFitPage() {
        let result = layout(
            [Self.letter, Self.letter], mode: ViewMode(arrangement: .facing), zoom: .fitPage,
            viewport: CGSize(width: 2416, height: 2000))

        #expect(result.scale == 2)  // (2416 - 8) / (600 * 2 + 4)
    }

    @Test(
        "fit modes pick the right axis",
        arguments: [
            (Zoom.fitPage, 0.5),  // min(1208/600, 400/800)
            (.fitWidth, 2.0133333),  // 1208 / 600
            (.fitHeight, 0.5),  // 400 / 800
            (.shrinkToFit, 0.5),
        ])
    func fitAxis(zoom: Zoom, expected: CGFloat) {
        let result = layout([Self.letter], zoom: zoom, viewport: CGSize(width: 1216, height: 404))
        #expect(abs(result.scale - expected) < 0.0001)
    }

    @Test("shrink to fit never enlarges small pages")
    func shrinkToFitCaps() {
        let result = layout(
            [CGSize(width: 100, height: 100)], zoom: .shrinkToFit, viewport: CGSize(width: 1000, height: 1000))
        #expect(result.scale == 1)
    }

    @Test("fit content zooms to the content box")
    func fitContent() {
        let result = layout(
            [Self.letter], zoom: .fitContent, viewport: CGSize(width: 408, height: 2000),
            contentBoxes: [CGRect(x: 100, y: 100, width: 200, height: 300)])

        #expect(result.scale == 2)  // 400 / 200
    }

    @Test("continuous fit content fits the current page's content", arguments: [(0, 0.5), (1, 1.0)])
    func fitContentCurrentPage(current: Int, expected: CGFloat) {
        let result = layout(
            [Self.letter, Self.letter], zoom: .fitContent, viewport: CGSize(width: 308, height: 5000), current: current,
            contentBoxes: [nil, CGRect(x: 150, y: 0, width: 300, height: 800)])

        #expect(result.scale == expected)
    }

    @Test("a quarter turn swaps page dimensions")
    func rotated() {
        let result = layout([Self.letter], zoom: .actualSize, viewport: CGSize(width: 100, height: 100), rotation: 90)

        #expect(result.pageFrames[0]?.size == CGSize(width: 800, height: 600))
    }

    @Test("a half turn puts the first page at the bottom")
    func upsideDown() {
        let result = layout(
            Array(repeating: Self.letter, count: 2), zoom: .actualSize, viewport: CGSize(width: 608, height: 100),
            rotation: 180)

        let first = try! #require(result.pageFrames[0])
        let second = try! #require(result.pageFrames[1])
        #expect(first.minY > second.minY)
        #expect(first.maxY == result.canvasSize.height - 2)
    }

    @Test("the current page is the one covering most of the view")
    func mostVisible() {
        let result = layout(
            Array(repeating: Self.letter, count: 3), zoom: .fitWidth, viewport: CGSize(width: 608, height: 400))

        #expect(result.mostVisiblePage(in: CGRect(x: 0, y: 0, width: 608, height: 400)) == 0)
        #expect(result.mostVisiblePage(in: CGRect(x: 0, y: 700, width: 608, height: 400)) == 1)
        #expect(result.mostVisiblePage(in: CGRect(x: 0, y: 9000, width: 608, height: 400)) == nil)
    }
}

@Suite("Zoom")
struct ZoomTests {
    @Test(
        "steps through Sumatra's zoom levels",
        arguments: [
            (100.0, true, Zoom.percent(125)),
            (100.0, false, .percent(75)),
            (110.0, true, .percent(125)),
            (110.0, false, .percent(100)),
            (8.33, false, .percent(8.33)),
            (6400.0, true, .percent(6400)),
            (5000.0, true, .percent(6400)),
        ])
    func steps(current: CGFloat, zoomIn: Bool, expected: Zoom) {
        // fit values far away so they never interfere
        #expect(Zoom.step(from: current, zoomIn: zoomIn, fitPage: 1, fitWidth: 2) == expected)
    }

    @Test("stops at fit page and fit width on the way")
    func fitStops() {
        #expect(Zoom.step(from: 100, zoomIn: true, fitPage: 110, fitWidth: 140) == .fitPage)
        #expect(Zoom.step(from: 110, zoomIn: true, fitPage: 110, fitWidth: 120) == .fitWidth)
        #expect(Zoom.step(from: 150, zoomIn: false, fitPage: 110, fitWidth: 140) == .fitWidth)
        #expect(Zoom.step(from: 140, zoomIn: false, fitPage: 130, fitWidth: 140) == .fitPage)
    }

    @Test("Z cycles through the fit modes")
    func toggle() {
        var zoom = Zoom.fitPage
        var seen: [Zoom] = []
        for _ in 0..<5 {
            zoom = zoom.toggled
            seen.append(zoom)
        }
        #expect(seen == [.fitWidth, .fitHeight, .fitContent, .shrinkToFit, .fitPage])
        #expect(Zoom.percent(250).toggled == .fitPage)
    }

    @Test("clamps absolute zoom to the supported range")
    func clamp() {
        #expect(Zoom.clamped(1) == .percent(8.33))
        #expect(Zoom.clamped(99_999) == .percent(6400))
        #expect(Zoom.clamped(150) == .percent(150))
    }
}

@Suite("Page geometry")
struct PageGeometryTests {
    private static let page = CGSize(width: 100, height: 200)

    @Test("maps corners for each rotation", arguments: [0, 90, 180, 270])
    func corners(rotation: Int) {
        let rotated = rotation % 180 == 0 ? CGSize(width: 200, height: 400) : CGSize(width: 400, height: 200)
        let frame = CGRect(origin: CGPoint(x: 10, y: 20), size: rotated)
        let geometry = PageGeometry(pageSize: Self.page, frame: frame, rotation: rotation)

        let topLeft = geometry.canvasPoint(fromPage: .zero)
        let expected: CGPoint =
            switch rotation {
            case 90: CGPoint(x: 410, y: 20)  // top-right of the frame
            case 180: CGPoint(x: 210, y: 420)  // bottom-right
            case 270: CGPoint(x: 10, y: 220)  // bottom-left
            default: CGPoint(x: 10, y: 20)
            }
        #expect(topLeft == expected)
        #expect(geometry.scale == 2)
    }

    @Test("round-trips points through canvas space", arguments: [0, 90, 180, 270])
    func roundTrip(rotation: Int) {
        let rotated = rotation % 180 == 0 ? Self.page : CGSize(width: 200, height: 100)
        let frame = CGRect(origin: CGPoint(x: 5, y: 7), size: rotated)
        let geometry = PageGeometry(pageSize: Self.page, frame: frame, rotation: rotation)
        let point = CGPoint(x: 30, y: 150)

        let back = geometry.pagePoint(fromCanvas: geometry.canvasPoint(fromPage: point))

        #expect(abs(back.x - point.x) < 0.001 && abs(back.y - point.y) < 0.001)
    }

    @Test("maps the whole page onto its frame", arguments: [0, 90, 180, 270])
    func wholePage(rotation: Int) {
        let rotated = rotation % 180 == 0 ? Self.page : CGSize(width: 200, height: 100)
        let frame = CGRect(origin: CGPoint(x: 5, y: 7), size: rotated)
        let geometry = PageGeometry(pageSize: Self.page, frame: frame, rotation: rotation)

        #expect(geometry.canvasRect(fromPage: CGRect(origin: .zero, size: Self.page)) == frame)
    }
}
