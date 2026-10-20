import CoreGraphics

/// Maps between a page's own space (unrotated, points, top-left origin) and
/// its frame on the canvas, which is scaled and rotated clockwise.
public struct PageGeometry: Hashable, Sendable {
    public var pageSize: CGSize
    public var frame: CGRect
    public var rotation: Int

    public init(pageSize: CGSize, frame: CGRect, rotation: Int) {
        self.pageSize = pageSize
        self.frame = frame
        self.rotation = ((rotation % 360) + 360) % 360
    }

    /// Canvas points per page point.
    public var scale: CGFloat {
        let width = rotation % 180 == 0 ? pageSize.width : pageSize.height
        return width > 0 ? frame.width / width : 1
    }

    /// Page space → canvas space.
    public var transform: CGAffineTransform {
        let s = scale
        let w = pageSize.width * s
        let h = pageSize.height * s
        let rotate: CGAffineTransform =
            switch rotation {
            case 90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
            case 180: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
            case 270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
            default: .identity
            }
        return CGAffineTransform(scaleX: s, y: s)
            .concatenating(rotate)
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
    }

    public func canvasPoint(fromPage point: CGPoint) -> CGPoint {
        point.applying(transform)
    }

    public func pagePoint(fromCanvas point: CGPoint) -> CGPoint {
        point.applying(transform.inverted())
    }

    public func canvasRect(fromPage rect: CGRect) -> CGRect {
        rect.applying(transform)
    }

    public func pageRect(fromCanvas rect: CGRect) -> CGRect {
        rect.applying(transform.inverted())
    }
}
