import Foundation

/// Parses PDF date strings (ISO 32000-1 §7.9.4): `D:YYYYMMDDHHmmSSOHH'mm'`.
/// Every component after the year is optional; a missing offset means UTC.
enum PDFDate {
    static func parse(_ raw: String) -> Date? {
        var s = Substring(raw.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("D:") { s = s.dropFirst(2) }

        func take(_ n: Int) -> Int? {
            guard s.count >= n, let value = Int(s.prefix(n)) else { return nil }
            s = s.dropFirst(n)
            return value
        }

        guard let year = take(4) else { return nil }
        var parts = DateComponents(year: year, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        parts.month = take(2) ?? 1
        parts.day = take(2) ?? 1
        parts.hour = take(2) ?? 0
        parts.minute = take(2) ?? 0
        parts.second = take(2) ?? 0

        var offset = 0
        if let sign = s.first, sign == "+" || sign == "-" {
            s = s.dropFirst()
            let hours = take(2) ?? 0
            if s.first == "'" { s = s.dropFirst() }
            let minutes = take(2) ?? 0
            offset = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        }

        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        calendar.timeZone = zone
        parts.calendar = calendar
        guard parts.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: parts)
    }
}
