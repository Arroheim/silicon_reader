import Foundation

/// The rows of SumatraPDF's Document Properties dialog, in its order. Absent
/// values are left out rather than shown empty.
public enum DocumentProperties {
    public struct Row: Equatable, Sendable {
        public var label: String
        public var value: String
    }

    public static func rows(
        url: URL, fileSize: Int64?, metadata: DocumentMetadata, pageCount: Int, firstPageSize: CGSize?,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> [Row] {
        let dates = DateFormatter()
        dates.locale = locale
        dates.timeZone = timeZone
        dates.dateStyle = .long
        dates.timeStyle = .medium

        var rows: [Row] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            rows.append(Row(label: label, value: value))
        }
        add("File", url.path)
        add("Title", metadata.title)
        add("Subject", metadata.subject)
        add("Author", metadata.author)
        add("Keywords", metadata.keywords)
        add("Created", metadata.creationDate.map(dates.string(from:)))
        add("Modified", metadata.modificationDate.map(dates.string(from:)))
        add("Application", metadata.creator)
        add("PDF Producer", metadata.producer)
        add("Format", metadata.format)
        add("File Size", fileSize.map { formatSize($0, locale: locale) })
        add("Number of Pages", String(pageCount))
        add("Page Size", firstPageSize.map { formatPageSize($0, locale: locale) })
        add("Encryption", metadata.encryption)
        return rows
    }

    /// "2.34 MB (2,457,600 Bytes)" like SumatraPDF.
    static func formatSize(_ bytes: Int64, locale: Locale) -> String {
        let short = ByteCountFormatter()
        short.countStyle = .file
        let count = NumberFormatter()
        count.locale = locale
        count.numberStyle = .decimal
        let exact = count.string(from: NSNumber(value: bytes)) ?? String(bytes)
        return "\(short.string(fromByteCount: bytes)) (\(exact) Bytes)"
    }

    /// Metric or imperial by locale, plus the paper name when it is a standard size.
    static func formatPageSize(_ size: CGSize, locale: Locale) -> String {
        let usesMetric = locale.measurementSystem != .us
        let dims: String
        if usesMetric {
            let mm = { (points: CGFloat) in Int((points / 72 * 25.4).rounded()) }
            dims = "\(mm(size.width)) × \(mm(size.height)) mm"
        } else {
            let inch = { (points: CGFloat) in String(format: "%.2f", points / 72) }
            dims = "\(inch(size.width)) × \(inch(size.height)) in"
        }
        return paperName(for: size).map { "\(dims) (\($0))" } ?? dims
    }

    /// Standard paper sizes in points, either orientation, within 1.5 pt.
    static func paperName(for size: CGSize) -> String? {
        let papers: [(String, CGFloat, CGFloat)] = [
            ("A3", 842, 1191), ("A4", 595, 842), ("A5", 420, 595), ("B5", 499, 709),
            ("Letter", 612, 792), ("Legal", 612, 1008), ("Tabloid", 792, 1224),
        ]
        let w = min(size.width, size.height)
        let h = max(size.width, size.height)
        return papers.first { abs($0.1 - w) <= 1.5 && abs($0.2 - h) <= 1.5 }?.0
    }

    /// Tab-separated "Label: value" lines for the clipboard.
    public static func text(_ rows: [Row]) -> String {
        rows.map { "\($0.label):\t\($0.value)" }.joined(separator: "\n")
    }
}
