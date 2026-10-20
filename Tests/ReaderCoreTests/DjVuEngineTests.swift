import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("DjVu engine")
struct DjVuEngineTests {
    @Test("opens a multi-page document with positive page sizes")
    func geometry() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("lizard2002.djvu"))

        #expect(engine.pageCount > 0)
        for index in 0..<engine.pageCount {
            let size = try engine.pageSize(at: index)
            #expect(size.width > 100 && size.height > 100, "page \(index): \(size)")
        }
    }

    @Test("renders at no less than the requested resolution", arguments: [0.5, 1.0, 2.0])
    func render(scale: CGFloat) throws {
        let engine = try DjVuEngine(url: try Fixtures.url("lizard2002.djvu"))
        let size = try engine.pageSize(at: 0)

        let image = try engine.render(page: 0, scale: scale)

        #expect(CGFloat(image.width) >= (size.width * scale).rounded(.down))
        #expect(CGFloat(image.height) >= (size.height * scale).rounded(.down))
    }

    @Test(
        "picks the largest subsample that keeps the target resolution",
        arguments: [
            (dpi: 300, scale: 1.0, expected: 4),  // 300 / 72
            (dpi: 300, scale: 2.0, expected: 2),  // 300 / 144
            (dpi: 300, scale: 5.0, expected: 1),  // upscaling: full resolution
            (dpi: 600, scale: 0.5, expected: 16),  // 600 / 36
            (dpi: 300, scale: 0.0, expected: 1),
        ])
    func subsample(dpi: Int, scale: CGFloat, expected: Int) {
        #expect(DjVuEngine.subsample(dpi: dpi, scale: scale) == expected)
    }

    @Test("fails to open a corrupt file")
    func corruptFile() throws {
        let url = try Fixtures.temporaryFile("broken.djvu", contents: Data("AT&TFORMgarbage".utf8))

        #expect(throws: EngineError.self) { try DjVuEngine(url: url) }
    }
}
