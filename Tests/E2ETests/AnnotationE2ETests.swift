import Foundation
import ReaderCore
import Testing

/// Annotations end to end: made through the same keys and menus as a user,
/// always on a copy, because saving rewrites the file.
@Suite("Annotations end-to-end", .serialized)
struct AnnotationE2ETests {
    private static func copyOfPDF() throws -> URL {
        let copy = AppSession.temporaryDirectory().appendingPathComponent("annotated.pdf")
        try FileManager.default.copyItem(at: Documents.pdf, to: copy)
        return copy
    }

    @Test("highlight, underline and strike-out mark the selected text")
    func markup() throws {
        let app = try AppSession(documents: [try Self.copyOfPDF()])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.send(ControlRequest(.key, chars: "a")).handled == false, "nothing selected")

        for (key, kind) in [("a", AnnotationKind.highlight), ("u", .underline), ("x", .strikeOut)] {
            try app.send(ControlRequest(.select, page: 0, start: 0, end: 12))
            let state = try app.press(key)
            #expect(state.annotations.last == kind)
            #expect(state.selectedText.isEmpty, "the selection gives way to the mark")
        }
        let state = try app.waitUntilSettled()
        #expect(state.annotations.count == 3)
        #expect(state.hasUnsavedChanges)
    }

    @Test("a picked annotation can be deleted with ⌦ or ⌫, otherwise ⌫ stays Back")
    func delete() throws {
        let app = try AppSession(documents: [try Self.copyOfPDF()])
        defer { try? app.quit() }
        try app.waitUntilSettled()
        try app.send(ControlRequest(.annotate, name: "note", text: "First", page: 0))
        try app.send(ControlRequest(.annotate, name: "stroke", page: 0))
        #expect(try app.state().annotations == [.note, .freehand])

        try app.send(ControlRequest(.annotate, name: "pick", page: 0, start: 1))
        #expect(try app.state().pickedAnnotation == 1)
        #expect(try app.press("delete").annotations == [.note])

        try app.send(ControlRequest(.annotate, name: "pick", page: 0, start: 0))
        let state = try app.press("backspace")
        #expect(state.annotations.isEmpty)
        #expect(state.pickedAnnotation == nil)

        try app.press("end")
        #expect(try app.press("backspace").page == 0, "nothing picked: Back")
    }

    @Test("Esc lets go of the picked annotation before the selection")
    func escape() throws {
        let app = try AppSession(documents: [try Self.copyOfPDF()])
        defer { try? app.quit() }
        try app.waitUntilSettled()
        try app.send(ControlRequest(.annotate, name: "note", text: "Note", page: 0))
        try app.send(ControlRequest(.annotate, name: "pick", page: 0, start: 0))
        try app.send(ControlRequest(.select, page: 0, start: 0, end: 5))

        let first = try app.press("escape")
        #expect(first.pickedAnnotation == nil)
        #expect(!first.selectedText.isEmpty)
        #expect(try app.press("escape").selectedText.isEmpty)
    }

    @Test("Draw mode toggles with D and ends with Esc")
    func drawMode() throws {
        let app = try AppSession(documents: [try Self.copyOfPDF()])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.press("d").isDrawing)
        #expect(try !app.press("d").isDrawing)
        #expect(try app.press("d").isDrawing)
        #expect(try !app.press("escape").isDrawing)
    }

    @Test("saving writes annotations into the file, and they are there next time")
    func saveAndReopen() throws {
        let file = try Self.copyOfPDF()
        do {
            let app = try AppSession(documents: [file])
            defer { try? app.quit() }
            try app.waitUntilSettled()
            try app.send(ControlRequest(.select, page: 0, start: 0, end: 12))
            try app.press("a")
            try app.send(ControlRequest(.annotate, name: "note", text: "Kept", page: 0))
            #expect(try app.state().hasUnsavedChanges)

            #expect(try app.press("s", "cmd", "option").hasUnsavedChanges == false)
            #expect(try app.waitUntilSettled().document == file.path, "no reload needed")
        }

        let reopened = try AppSession(documents: [file])
        defer { try? reopened.quit() }
        let state = try reopened.waitUntilSettled()
        #expect(state.annotations == [.highlight, .note])
        #expect(!state.hasUnsavedChanges)
    }

    @Test("Save Annotations needs something to save")
    func saveDisabled() throws {
        let app = try AppSession(documents: [try Self.copyOfPDF()])
        defer { try? app.quit() }
        try app.waitUntilSettled()

        #expect(try app.send(ControlRequest(.menu, text: "Annotate")).items?.contains("(Save Annotations)") == true)
    }

    @Test("a file changed on disk doesn't throw away unsaved annotations")
    func keepsEditsOnExternalChange() throws {
        let file = try Self.copyOfPDF()
        let app = try AppSession(documents: [file])
        defer { try? app.quit() }
        try app.waitUntilSettled()
        try app.send(ControlRequest(.annotate, name: "note", text: "Precious", page: 0))

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()

        let deadline = Date().addingTimeInterval(5)
        while try !app.state().subtitle.contains("aren't saved"), Date() < deadline {
            usleep(50_000)
        }
        let state = try app.state()
        #expect(state.subtitle.contains("aren't saved"))
        #expect(state.annotations == [.note])
    }

    @Test("DjVu can't be annotated")
    func djvu() throws {
        let app = try AppSession(documents: [Documents.spec])
        defer { try? app.quit() }
        try app.waitUntilSettled()
        try app.send(ControlRequest(.select, page: 0, start: 0, end: 10))

        #expect(try app.send(ControlRequest(.resolve, name: "annotateHighlight")).handled == false)
        #expect(try app.send(ControlRequest(.resolve, name: "toggleDrawing")).handled == false)
        #expect(try app.send(ControlRequest(.key, chars: "d")).handled == false)
    }
}
