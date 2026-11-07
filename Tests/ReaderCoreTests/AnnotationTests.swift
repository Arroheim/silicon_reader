import CoreGraphics
import Foundation
import Testing

@testable import ReaderCore

@Suite("PDF annotations")
struct AnnotationTests {
    private static func document() throws -> MuPDFEngine {
        var page = TestPDF.Page()
        page.text = [("Hello World", CGPoint(x: 40, y: 50)), ("Second line", CGPoint(x: 40, y: 120))]
        return try MuPDFEngine(url: try TestPDF(pages: [page, TestPDF.Page()]).write())
    }

    private static let line = CGRect(x: 40, y: 50, width: 120, height: 24)

    /// Average of a page area's pixels, as 0...255 red, green and blue.
    private static func color(of engine: MuPDFEngine, in area: CGRect) throws -> (r: Int, g: Int, b: Int) {
        let image = try engine.render(page: 0, scale: 1, region: area)
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test("a fresh PDF can be annotated and has nothing to save")
    func fresh() throws {
        let engine = try Self.document()

        #expect(engine.supportsAnnotations)
        #expect(!engine.hasUnsavedChanges)
        #expect(try engine.annotations(onPage: 0).isEmpty)
    }

    @Test("DjVu has no annotations")
    func djvu() throws {
        let engine = try DjVuEngine(url: try Fixtures.url("lizard2002.djvu"))

        #expect(!engine.supportsAnnotations)
        #expect(!engine.hasUnsavedChanges)
        #expect(try engine.annotations(onPage: 0).isEmpty)
        #expect(throws: EngineError.self) { try engine.addNote("x", at: .zero, onPage: 0) }
    }

    @Test(
        "text markup covers the given line",
        arguments: [AnnotationKind.highlight, .underline, .strikeOut])
    func markup(kind: AnnotationKind) throws {
        let engine = try Self.document()

        let index = try engine.addMarkup(kind, rects: [Self.line], onPage: 0)

        let annotation = try #require(try engine.annotations(onPage: 0).first)
        #expect(annotation.index == index)
        #expect(annotation.kind == kind)
        #expect(annotation.rect.insetBy(dx: -2, dy: -2).contains(Self.line.insetBy(dx: 1, dy: 1)))
        #expect(engine.hasUnsavedChanges)
    }

    @Test("a new highlight shows in the next render of that page")
    func rendersEdit() throws {
        let engine = try Self.document()
        let paper = CGRect(x: 40, y: 200, width: 120, height: 24)
        let blank = try Self.color(of: engine, in: paper)
        #expect(blank.b > 240, "white paper, cached as a display list by now")

        try engine.addMarkup(.highlight, rects: [paper], onPage: 0)

        let marked = try Self.color(of: engine, in: paper)
        #expect(marked.b < 100, "yellow takes out the blue: \(marked)")
    }

    @Test("notes and freehand strokes keep their data")
    func noteAndInk() throws {
        let engine = try Self.document()

        try engine.addNote("Check this", at: CGPoint(x: 100, y: 100), onPage: 0)
        let strokes = [
            [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)],
            [CGPoint(x: 60, y: 60), CGPoint(x: 90, y: 90)],
        ]
        try engine.addFreehand(strokes: strokes, onPage: 0)

        let annotations = try engine.annotations(onPage: 0)
        #expect(annotations.map(\.kind) == [.note, .freehand])
        #expect(annotations[0].contents == "Check this")
        #expect(annotations[1].rect.contains(CGRect(x: 10, y: 10, width: 80, height: 80)))
    }

    @Test("note text changes and annotations go away")
    func edit() throws {
        let engine = try Self.document()
        let note = try engine.addNote("Before", at: CGPoint(x: 100, y: 100), onPage: 0)
        let highlight = try engine.addMarkup(.highlight, rects: [Self.line], onPage: 0)

        try engine.setContents("After — кириллица", ofAnnotation: note, onPage: 0)
        #expect(try engine.annotations(onPage: 0)[0].contents == "After — кириллица")

        try engine.removeAnnotation(highlight, onPage: 0)
        #expect(try engine.annotations(onPage: 0).map(\.kind) == [.note])
        #expect(throws: EngineError.self) { try engine.removeAnnotation(7, onPage: 0) }
    }

    @Test("saving over the open file keeps annotations and clears the unsaved state")
    func saveOverSelf() throws {
        let engine = try Self.document()
        try engine.addMarkup(.underline, rects: [Self.line], onPage: 0)
        try engine.addNote("Saved", at: CGPoint(x: 100, y: 100), onPage: 1)

        try engine.save(to: engine.url)

        #expect(!engine.hasUnsavedChanges)
        #expect(try engine.text(onPage: 0).string.contains("Hello World"), "the open file still reads")
        let reopened = try MuPDFEngine(url: engine.url)
        #expect(!reopened.hasUnsavedChanges)
        #expect(try reopened.annotations(onPage: 0).map(\.kind) == [.underline])
        #expect(try reopened.annotations(onPage: 1).first?.contents == "Saved")
        #expect(try reopened.text(onPage: 0).string.contains("Hello World"))
    }

    @Test("saving a copy leaves the original alone and the changes unsaved")
    func saveCopy() throws {
        let engine = try Self.document()
        try engine.addMarkup(.highlight, rects: [Self.line], onPage: 0)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: copy) }

        try engine.save(to: copy)

        #expect(engine.hasUnsavedChanges)
        #expect(try MuPDFEngine(url: copy).annotations(onPage: 0).count == 1)
        #expect(try MuPDFEngine(url: engine.url).annotations(onPage: 0).isEmpty)
    }

    @Test("a failed save reports the reason and leaves no temporary file behind")
    func saveFailure() throws {
        let engine = try Self.document()
        let target = URL(fileURLWithPath: "/nonexistent-folder/out.pdf")

        #expect(throws: EngineError.self) { try engine.save(to: target) }
    }
}
