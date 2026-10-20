import AppKit
import ReaderCore

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let pageView: PageStackView

    init(engine: any DocumentEngine) {
        pageView = PageStackView(engine: engine)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = PageStackView.canvasColor
        scrollView.documentView = pageView

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

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidResize),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        pageView.layoutPages(forWidth: scrollView.contentView.bounds.width)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isSettled: Bool { pageView.isSettled }

    /// PNG of the window content as currently drawn.
    func snapshotPNG() -> Data? {
        guard let view = window?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @objc private func clipViewDidResize(_ note: Notification) {
        guard let clip = note.object as? NSClipView else { return }
        pageView.layoutPages(forWidth: clip.bounds.width)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }
}
