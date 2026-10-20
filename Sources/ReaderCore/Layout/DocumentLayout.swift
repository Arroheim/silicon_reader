import CoreGraphics

/// How pages are arranged in rows.
public enum PageArrangement: String, Hashable, Sendable, CaseIterable, Codable {
    /// One page per row.
    case single
    /// Two pages per row: 1-2, 3-4, …
    case facing
    /// Two pages per row with the cover alone: 1, 2-3, 4-5, …
    case book
}

public struct ViewMode: Hashable, Sendable, Codable {
    public var arrangement: PageArrangement
    /// Continuous: all rows are laid out and scroll; otherwise only the row
    /// holding the current page is shown.
    public var continuous: Bool

    public init(arrangement: PageArrangement = .single, continuous: Bool = true) {
        self.arrangement = arrangement
        self.continuous = continuous
    }

    var columns: Int { arrangement == .single ? 1 : 2 }
}

public struct EdgeInsetsF: Hashable, Sendable {
    public var top, left, bottom, right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Inputs to a layout pass. Sizes are in PDF points and view points.
public struct LayoutParams: Hashable, Sendable {
    /// Unrotated page sizes in points.
    public var pageSizes: [CGSize]
    /// Bounding box of the drawn content per page (unrotated, top-left
    /// origin); used by fit content. Missing entries mean the whole page.
    public var contentBoxes: [CGRect?]
    public var mode: ViewMode
    public var zoom: Zoom
    /// Clockwise rotation in degrees: 0, 90, 180 or 270.
    public var rotation: Int
    public var viewport: CGSize
    /// First page of the shown row in non-continuous modes (0-based).
    public var currentPage: Int
    /// SumatraPDF defaults: 2/4/2/4 window margin, 4x4 page spacing.
    public static let defaultMargin = EdgeInsetsF(top: 2, left: 4, bottom: 2, right: 4)
    public var margin = defaultMargin
    public var spacing = CGSize(width: 4, height: 4)

    public init(
        pageSizes: [CGSize], contentBoxes: [CGRect?] = [], mode: ViewMode = ViewMode(), zoom: Zoom = .fitPage,
        rotation: Int = 0, viewport: CGSize, currentPage: Int = 0
    ) {
        self.pageSizes = pageSizes
        self.contentBoxes = contentBoxes
        self.mode = mode
        self.zoom = zoom
        self.rotation = rotation
        self.viewport = viewport
        self.currentPage = currentPage
    }
}

/// A row of pages laid out side by side.
public struct PageRow: Hashable, Sendable {
    public var pages: ClosedRange<Int>
}

/// Result of a layout pass: where each page sits on the canvas.
public struct DocumentLayout: Equatable, Sendable {
    /// View points per PDF point (1.0 == 100%).
    public var scale: CGFloat
    public var canvasSize: CGSize
    /// Frame of each page on the canvas (rotated size), nil if not shown.
    public var pageFrames: [CGRect?]
    public var rows: [PageRow]
    public var rotation: Int

    public static let empty = DocumentLayout(scale: 1, canvasSize: .zero, pageFrames: [], rows: [], rotation: 0)

    public var zoomPercent: CGFloat { scale * 100 }

    public func row(containing page: Int) -> PageRow? {
        rows.first { $0.pages.contains(page) }
    }

    /// Page covering the largest share of `visible` (SumatraPDF's CurrentPageNo).
    public func mostVisiblePage(in visible: CGRect) -> Int? {
        var best: (page: Int, ratio: CGFloat)?
        for (page, frame) in pageFrames.enumerated() {
            guard let frame, frame.height > 0 else { continue }
            let overlap = frame.intersection(visible)
            guard !overlap.isNull else { continue }
            let ratio = (overlap.width * overlap.height) / (frame.width * frame.height)
            if ratio > (best?.ratio ?? 0) { best = (page, ratio) }
        }
        return best?.page
    }

    /// Geometry for mapping between page space and canvas space.
    public func geometry(forPage page: Int, pageSize: CGSize) -> PageGeometry? {
        guard page < pageFrames.count, let frame = pageFrames[page] else { return nil }
        return PageGeometry(pageSize: pageSize, frame: frame, rotation: rotation)
    }
}

public enum LayoutEngine {
    /// Rows for an arrangement (SumatraPDF's CollectFacingRows without spreads).
    public static func rows(pageCount: Int, arrangement: PageArrangement) -> [PageRow] {
        guard pageCount > 0 else { return [] }
        if arrangement == .single {
            return (0..<pageCount).map { PageRow(pages: $0...$0) }
        }
        var rows: [PageRow] = []
        var page = 0
        while page < pageCount {
            var last = page
            if !(arrangement == .book && page == 0) && page + 1 < pageCount {
                last += 1
            }
            rows.append(PageRow(pages: page...last))
            page = last + 1
        }
        return rows
    }

    /// Port of SumatraPDF's DocumentLayout::RelayoutRows for vertical layouts.
    public static func layout(_ params: LayoutParams) -> DocumentLayout {
        let pageCount = params.pageSizes.count
        let rotated = params.rotation % 180 != 0
        let sizes = params.pageSizes.map { rotated ? CGSize(width: $0.height, height: $0.width) : $0 }
        let allRows = rows(pageCount: pageCount, arrangement: params.mode.arrangement)
        guard pageCount > 0, let firstRow = allRows.first else {
            return DocumentLayout(
                scale: 1, canvasSize: params.viewport, pageFrames: [], rows: [], rotation: params.rotation)
        }

        let current = min(max(params.currentPage, 0), pageCount - 1)
        let shownRows =
            params.mode.continuous ? allRows : [allRows.first { $0.pages.contains(current) } ?? firstRow]
        let scale = realScale(params, sizes: sizes, shownRows: shownRows)

        var frames = [CGRect?](repeating: nil, count: pageCount)
        var y = params.margin.top
        var columnWidth: [CGFloat] = [0, 0]
        var fullRowWidth: CGFloat = 0
        let single = params.mode.arrangement == .single
        let book = params.mode.arrangement == .book

        for row in shownRows {
            var rowHeight: CGFloat = 0
            let isCover = book && row.pages == 0...0
            for page in row.pages {
                let size = CGSize(
                    width: (sizes[page].width * scale).rounded(), height: (sizes[page].height * scale).rounded())
                frames[page] = CGRect(origin: CGPoint(x: 0, y: y), size: size)
                rowHeight = max(rowHeight, size.height)
                if single {
                    fullRowWidth = max(fullRowWidth, size.width)
                } else {
                    let column = page - row.pages.lowerBound + (isCover ? 1 : 0)
                    columnWidth[column] = max(columnWidth[column], size.width)
                }
            }
            y += rowHeight + params.spacing.height
        }
        var canvasHeight = y + params.margin.bottom - params.spacing.height

        if pageCount == 1 {
            if book { columnWidth[0] = columnWidth[1] } else { columnWidth[1] = columnWidth[0] }
        }
        let pagesWidth = single ? fullRowWidth : columnWidth[0] + params.spacing.width + columnWidth[1]
        var canvasWidth = params.margin.left + pagesWidth + params.margin.right
        var offsetX: CGFloat = 0
        if canvasWidth < params.viewport.width {
            offsetX = ((params.viewport.width - canvasWidth) / 2).rounded(.down)
            canvasWidth = params.viewport.width
        }

        for row in shownRows {
            let isCover = book && row.pages == 0...0
            let left = offsetX + params.margin.left
            for page in row.pages {
                guard var frame = frames[page] else { continue }
                if single || (isCover && !params.mode.continuous) {
                    frame.origin.x = left + ((pagesWidth - frame.width) / 2).rounded(.down)
                } else if !isCover && page == row.pages.lowerBound {
                    frame.origin.x = left + columnWidth[0] - frame.width
                } else {
                    frame.origin.x = left + columnWidth[0] + params.spacing.width
                }
                frames[page] = frame
            }
        }

        // Center vertically when everything fits (FinishRelayout).
        if canvasHeight < params.viewport.height {
            let offsetY = ((params.viewport.height - canvasHeight) / 2).rounded(.down)
            frames = frames.map { $0?.offsetBy(dx: 0, dy: offsetY) }
        }
        if params.zoom == .fitPage && !params.mode.continuous {
            canvasHeight = min(canvasHeight, params.viewport.height)
            canvasWidth = min(canvasWidth, params.viewport.width)
        }

        // A half turn reads bottom-up: mirror the stack so page 1 ends up at the bottom.
        if params.rotation == 180 {
            let height = max(canvasHeight, params.viewport.height)
            frames = frames.map { frame in
                frame.map { CGRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height) }
            }
        }

        return DocumentLayout(
            scale: scale,
            canvasSize: CGSize(
                width: max(canvasWidth, params.viewport.width), height: max(canvasHeight, params.viewport.height)),
            pageFrames: frames,
            rows: shownRows,
            rotation: params.rotation)
    }

    /// The real scale for a zoom: absolute zooms map directly; fit zooms take
    /// the smallest per-row fit so the largest shown page fits (CalcZoomReal).
    /// Fit content only considers the row holding the current page.
    static func realScale(_ params: LayoutParams, sizes: [CGSize], shownRows: [PageRow]) -> CGFloat {
        if case .percent(let percent) = params.zoom {
            return percent / 100
        }
        let area = CGSize(
            width: params.viewport.width - params.margin.left - params.margin.right,
            height: params.viewport.height - params.margin.top - params.margin.bottom)
        guard area.width > 0, area.height > 0 else { return 0.01 }

        // Fit content fits the row being read: measuring the content of every
        // page of a long document up front would be too slow.
        let current = min(max(params.currentPage, 0), sizes.count - 1)
        let rowsToFit = params.zoom == .fitContent ? shownRows.filter { $0.pages.contains(current) } : shownRows

        var scale = CGFloat.infinity
        for row in rowsToFit {
            let rowSize = rowExtent(row, params: params, sizes: sizes)
            guard rowSize.width > 0, rowSize.height > 0 else { continue }
            let fitX = area.width / rowSize.width
            let fitY = area.height / rowSize.height
            let fit: CGFloat
            switch params.zoom {
            case .fitWidth: fit = fitX
            case .fitHeight: fit = fitY
            case .shrinkToFit: fit = min(fitX, fitY, 1)
            default: fit = min(fitX, fitY)
            }
            scale = min(scale, fit)
        }
        return scale.isFinite ? max(scale, 0.01) : 1
    }

    /// Unscaled size a row needs: widths of its columns plus spacing, or the
    /// content box for fit content.
    private static func rowExtent(_ row: PageRow, params: LayoutParams, sizes: [CGSize]) -> CGSize {
        let columns = params.mode.columns
        if params.zoom == .fitContent {
            var box = CGRect.null
            var x: CGFloat = 0
            for page in row.pages {
                let content = rotatedContentBox(page, params: params, size: sizes[page])
                box = box.union(content.offsetBy(dx: x, dy: 0))
                x += sizes[page].width + params.spacing.width
            }
            return box.size
        }
        let widest = row.pages.map { sizes[$0].width }.max() ?? 0
        let tallest = row.pages.map { sizes[$0].height }.max() ?? 0
        return CGSize(width: widest * CGFloat(columns) + params.spacing.width * CGFloat(columns - 1), height: tallest)
    }

    private static func rotatedContentBox(_ page: Int, params: LayoutParams, size: CGSize) -> CGRect {
        let unrotated = params.pageSizes[page]
        guard page < params.contentBoxes.count, let box = params.contentBoxes[page], !box.isEmpty else {
            return CGRect(origin: .zero, size: size)
        }
        return PageGeometry(pageSize: unrotated, frame: CGRect(origin: .zero, size: size), rotation: params.rotation)
            .canvasRect(fromPage: box)
    }
}
