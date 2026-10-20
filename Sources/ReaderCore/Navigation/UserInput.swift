import CoreGraphics
import Foundation

/// Parsing of what the user types into the toolbar's page and zoom boxes.
public enum UserInput {
    /// A 1-based page number or a page label ("iv", "A-3") → 0-based index.
    ///
    /// Labels win over numbers when they match exactly, as in SumatraPDF, so a
    /// document whose page labelled "5" is the seventh page goes to the seventh.
    public static func page(_ text: String, pageCount: Int, label: (Int) -> String?) -> Int? {
        let input = text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return nil }
        if let labelled = (0..<pageCount).first(where: { label($0) == input }) {
            return labelled
        }
        guard let number = Int(input), (1...pageCount).contains(number) else { return nil }
        return number - 1
    }

    /// "150", "150%", "66.67 %" or a fit mode name → zoom. Absolute values are
    /// clamped to the supported range.
    public static func zoom(_ text: String) -> Zoom? {
        let input = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let fit = Self.fitNames.first(where: { $0.name.lowercased() == input })?.zoom {
            return fit
        }
        let number = input.hasSuffix("%") ? String(input.dropLast()).trimmingCharacters(in: .whitespaces) : input
        guard let value = Double(number.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return .clamped(CGFloat(value))
    }

    /// Display names for fit modes, in menu order.
    public static let fitNames: [(name: String, zoom: Zoom)] = [
        ("Fit Page", .fitPage),
        ("Fit Width", .fitWidth),
        ("Fit Height", .fitHeight),
        ("Fit Content", .fitContent),
        ("Shrink to Fit", .shrinkToFit),
    ]

    /// "125%", "66.67%", "8.33%": up to two decimals, no trailing zeros.
    public static func format(percent: CGFloat) -> String {
        let rounded = (percent * 100).rounded() / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: Double(rounded))) ?? "\(rounded)") + "%"
    }
}
