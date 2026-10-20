import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("Format detection")
struct DocumentOpenerTests {
    @Test(
        "detects format by header regardless of extension",
        arguments: [
            (header: "%PDF-1.7", name: "file.bin", expected: DocumentFormat.pdf),
            (header: "AT&TFORM", name: "file.pdf", expected: DocumentFormat.djvu),
        ])
    func byHeader(header: String, name: String, expected: DocumentFormat) throws {
        let url = try Fixtures.temporaryFile(name, contents: Data(header.utf8))
        #expect(DocumentFormat.detect(url) == expected)
    }

    @Test(
        "falls back to the extension for unknown headers",
        arguments: [
            ("a.PDF", DocumentFormat.pdf), ("a.djvu", .djvu), ("a.djv", .djvu), ("a.txt", nil),
        ] as [(String, DocumentFormat?)])
    func byExtension(name: String, expected: DocumentFormat?) throws {
        let url = try Fixtures.temporaryFile(name, contents: Data("????????".utf8))
        #expect(DocumentFormat.detect(url) == expected)
    }

    @Test("dispatches to the matching engine")
    func dispatch() throws {
        let pdf = try DocumentOpener.open(try TestPDF.make(pageSizes: [CGSize(width: 10, height: 10)]))
        let djvu = try DocumentOpener.open(try Fixtures.url("lizard2002.djvu"))

        #expect(pdf is MuPDFEngine)
        #expect(djvu is DjVuEngine)
    }

    @Test("rejects unsupported files")
    func unsupported() throws {
        let url = try Fixtures.temporaryFile("notes.txt", contents: Data("hello".utf8))
        #expect(throws: EngineError.unsupportedFormat(url)) { try DocumentOpener.open(url) }
    }
}
