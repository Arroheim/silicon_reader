import AppKit
import ReaderCore

/// The document window. Accepts PDF/DjVu files dropped anywhere on it, like
/// SumatraPDF's main window; the Dock icon takes drops through the app's
/// declared document types instead.
final class ReaderWindow: NSWindow, NSDraggingDestination {
    /// Opens the dropped documents; returns whether any was opened.
    var onDrop: (([URL]) -> Bool)?

    override init(
        contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        registerForDraggedTypes([.fileURL])
    }

    private static func documents(in info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.filter(DocumentOpener.canOpen)
    }

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.documents(in: sender).isEmpty ? [] : .copy
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = Self.documents(in: sender)
        guard !urls.isEmpty else { return false }
        return onDrop?(urls) ?? false
    }
}
