import CoreGraphics

/// Where a document page goes on a sheet of paper.
public struct PrintPlacement: Equatable, Sendable {
    /// Destination rect on the sheet (sheet coordinates, top-left origin).
    public var rect: CGRect
    /// Rotate the page a quarter turn (landscape page on portrait paper or vice versa).
    public var rotated: Bool
}

public enum PrintLayout {
    public enum Scaling: Sendable {
        /// Scale up or down to fill the printable area (SumatraPDF's "Fit to printable area").
        case fit
        /// Only scale down pages that don't fit ("Shrink pages to printable area").
        case shrink
    }

    /// Fits `pageSize` (points) into `printable`, centred, rotating it when that
    /// matches the paper's orientation better (SumatraPDF's auto-rotation).
    public static func place(
        pageSize: CGSize, in printable: CGRect, scaling: Scaling = .fit, autoRotate: Bool = true
    ) -> PrintPlacement {
        guard pageSize.width > 0, pageSize.height > 0, printable.width > 0, printable.height > 0 else {
            return PrintPlacement(rect: printable, rotated: false)
        }
        let pageLandscape = pageSize.width > pageSize.height
        let paperLandscape = printable.width > printable.height
        let rotated = autoRotate && pageLandscape != paperLandscape && pageSize.width != pageSize.height
        let size = rotated ? CGSize(width: pageSize.height, height: pageSize.width) : pageSize

        var scale = min(printable.width / size.width, printable.height / size.height)
        if scaling == .shrink { scale = min(scale, 1) }
        let w = size.width * scale
        let h = size.height * scale
        let rect = CGRect(x: printable.midX - w / 2, y: printable.midY - h / 2, width: w, height: h)
        return PrintPlacement(rect: rect, rotated: rotated)
    }
}
