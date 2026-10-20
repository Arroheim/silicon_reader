import CoreGraphics

/// A place in a document to come back to.
public struct DocumentPosition: Hashable, Sendable {
    public var page: Int
    /// Point in page space (top-left origin) shown at the top-left of the viewport.
    public var point: CGPoint

    public init(page: Int, point: CGPoint = .zero) {
        self.page = page
        self.point = point
    }
}

/// Browser-style back/forward history of jumps (links, outline, go to page).
///
/// Like SumatraPDF, only jumps are recorded, not scrolling; a new jump after
/// going back drops the forward entries.
public struct NavigationHistory: Sendable {
    private var back: [DocumentPosition] = []
    private var forward: [DocumentPosition] = []
    public let limit: Int

    public init(limit: Int = 50) {
        self.limit = limit
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Call before jumping away from `current`.
    public mutating func recordJump(from current: DocumentPosition) {
        if back.last != current {
            back.append(current)
            if back.count > limit { back.removeFirst() }
        }
        forward.removeAll()
    }

    /// Returns where to go back to, remembering `current` for forward.
    public mutating func goBack(from current: DocumentPosition) -> DocumentPosition? {
        guard let target = back.popLast() else { return nil }
        forward.append(current)
        return target
    }

    public mutating func goForward(from current: DocumentPosition) -> DocumentPosition? {
        guard let target = forward.popLast() else { return nil }
        back.append(current)
        return target
    }
}
