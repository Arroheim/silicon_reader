import CoreGraphics

/// Everything needed to show a document the way the user left it: reload,
/// duplicate in a new window and per-file state on disk.
public struct ViewState: Hashable, Sendable, Codable {
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

extension DocumentPosition: Codable {
    private enum CodingKeys: String, CodingKey { case page, x, y }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        let y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        self.init(page: try c.decode(Int.self, forKey: .page), point: CGPoint(x: x, y: y))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(page, forKey: .page)
        try c.encode(Double(point.x), forKey: .x)
        try c.encode(Double(point.y), forKey: .y)
    }
}

/// Stored like SumatraPDF's settings: "fit page", "fit width", … or a percentage number.
extension Zoom: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let percent = try? c.decode(Double.self) {
            self = .clamped(CGFloat(percent))
        } else if let name = try? c.decode(String.self), let zoom = UserInput.zoom(name) {
            self = zoom
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a zoom value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        if case .percent(let percent) = self {
            try c.encode(Double(percent))
        } else if let name = UserInput.fitNames.first(where: { $0.zoom == self })?.name {
            try c.encode(name.lowercased())
        }
    }
}
