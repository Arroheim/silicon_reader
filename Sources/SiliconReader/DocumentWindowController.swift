import AppKit
import ReaderCore

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let canvas: DocumentView

    init(engine: any DocumentEngine) {
        canvas = DocumentView(engine: engine)

        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DocumentView.canvasColor
        scrollView.documentView = canvas

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.contentView = scrollView
        window.title = engine.url.lastPathComponent
        window.representedURL = engine.url
        window.setFrameAutosaveName("DocumentWindow")
        window.tabbingMode = .preferred
        window.center()

        super.init(window: window)
        window.delegate = self
        window.initialFirstResponder = canvas

        let clip = scrollView.contentView
        clip.postsFrameChangedNotifications = true
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewFrameChanged), name: NSView.frameDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsChanged), name: NSView.boundsDidChangeNotification, object: clip)

        canvas.onStateChange = { [weak self] in self?.updateSubtitle() }
        canvas.viewportDidResize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas)
    }

    var isSettled: Bool { canvas.isSettled }

    /// Sends a menu action straight to the canvas (debug hook), regardless of focus.
    func perform(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: canvas, from: nil)
    }

    /// PNG of the window content as currently drawn.
    func snapshotPNG() -> Data? {
        guard let view = window?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private func updateSubtitle() {
        let zoom = Int(canvas.layout.zoomPercent.rounded())
        window?.subtitle = "Page \(canvas.currentPage + 1) of \(canvas.pageCount) · \(zoom)%"
    }

    @objc private func clipViewFrameChanged(_ note: Notification) {
        canvas.viewportDidResize()
    }

    @objc private func clipViewBoundsChanged(_ note: Notification) {
        canvas.viewportDidScroll()
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }
}
