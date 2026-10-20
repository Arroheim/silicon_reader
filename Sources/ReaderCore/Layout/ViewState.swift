import CoreGraphics

/// Everything needed to show a document the way the user left it: reload,
/// duplicate in a new window and (later) per-file state on disk.
public struct ViewState: Hashable, Sendable {
    public var mode: ViewMode
    public var zoom: Zoom
    public var rotation: Int
    public var position: DocumentPosition

    public init(mode: ViewMode = ViewMode(), zoom: Zoom = .fitPage, rotation: Int = 0, position: DocumentPosition) {
        self.mode = mode
        self.zoom = zoom
        self.rotation = rotation
        self.position = position
    }
}
