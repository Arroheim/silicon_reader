import Foundation

public enum DocumentFormat: Equatable, Sendable {
    case pdf
    case djvu

    /// Sniffs the file header first and falls back to the extension.
    public static func detect(_ url: URL) -> DocumentFormat? {
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 8)) ?? Data()
            if head.starts(with: Data("%PDF".utf8)) { return .pdf }
            if head.starts(with: Data("AT&TFORM".utf8)) { return .djvu }
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "djvu", "djv": return .djvu
        default: return nil
        }
    }
}

public enum DocumentOpener {
    public static func open(_ url: URL) throws -> any DocumentEngine {
        switch DocumentFormat.detect(url) {
        case .pdf: try MuPDFEngine(url: url)
        case .djvu: try DjVuEngine(url: url)
        case nil: throw EngineError.unsupportedFormat(url)
        }
    }
}
