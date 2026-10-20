import Foundation
import Testing

@testable import ReaderCore

@Suite("PDF dates")
struct PDFDateTests {
    private static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    @Test(
        "parses full and partial dates",
        arguments: [
            ("D:20241031153045Z", utc(2024, 10, 31, 15, 30, 45)),
            ("D:20241031153045+02'00'", utc(2024, 10, 31, 13, 30, 45)),
            ("D:20241031153045-05'30", utc(2024, 10, 31, 21, 0, 45)),
            ("D:2024103115", utc(2024, 10, 31, 15)),
            ("D:2024", utc(2024, 1, 1)),
            ("20241031", utc(2024, 10, 31)),
            (" D:20240229 ", utc(2024, 2, 29)),
        ])
    func valid(raw: String, expected: Date) {
        #expect(PDFDate.parse(raw) == expected)
    }

    @Test("rejects malformed dates", arguments: ["", "D:", "D:abcd", "D:20230230", "D:20241301"])
    func invalid(raw: String) {
        #expect(PDFDate.parse(raw) == nil)
    }
}
