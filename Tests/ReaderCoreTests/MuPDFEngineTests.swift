import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("MuPDF engine")
struct MuPDFEngineTests {
    @Test("reports page count and per-page sizes in points")
    func geometry() throws {
        let url = try TestPDF.make(pageSizes: [CGSize(width: 612, height: 792), CGSize(width: 300, height: 400)])
        let engine = try MuPDFEngine(url: url)

        #expect(engine.pageCount == 2)
        #expect(try engine.pageSize(at: 0) == CGSize(width: 612, height: 792))
        #expect(try engine.pageSize(at: 1) == CGSize(width: 300, height: 400))
    }

    @Test("renders at the requested scale, top-down", arguments: [1.0, 2.0])
    func render(scale: CGFloat) throws {
        let url = try TestPDF.make(pageSizes: [CGSize(width: 200, height: 100)])
        let engine = try MuPDFEngine(url: url)

        let pixels = Pixels(try engine.render(page: 0, scale: scale))

        #expect(pixels.width == Int(200 * scale))
        #expect(pixels.height == Int(100 * scale))
        let topLeft = pixels.rgb(x: pixels.width / 4, y: pixels.height / 4)
        let bottomRight = pixels.rgb(x: pixels.width * 3 / 4, y: pixels.height * 3 / 4)
        #expect(topLeft.r > 200 && topLeft.g < 60 && topLeft.b < 60, "expected red, got \(topLeft)")
        #expect(bottomRight == (255, 255, 255), "expected white, got \(bottomRight)")
    }

    @Test("rejects out-of-range pages")
    func invalidPage() throws {
        let engine = try MuPDFEngine(url: try TestPDF.make(pageSizes: [CGSize(width: 100, height: 100)]))

        #expect(throws: EngineError.invalidPage(1)) { try engine.render(page: 1, scale: 1) }
        #expect(throws: EngineError.invalidPage(-1)) { try engine.pageSize(at: -1) }
    }

    @Test("fails to open a corrupt file with a reason")
    func corruptFile() throws {
        let url = try Fixtures.temporaryFile("broken.pdf", contents: Data("not a pdf".utf8))

        #expect {
            try MuPDFEngine(url: url)
        } throws: { error in
            guard case .openFailed(_, let reason) = error as? EngineError else { return false }
            return !reason.isEmpty
        }
    }
}
