import AppKit
import ReaderCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [MainWindowController] = []
    private var openedAtLaunch = false

    /// `-library path.json` points the app at another library (tests, smoke runs)
    /// so they never touch the user's history.
    private let library = Library(
        url: UserDefaults.standard.string(forKey: "library").map { URL(fileURLWithPath: $0) } ?? Library.defaultURL)
    private lazy var thumbnails = ThumbnailStore(
        directory: library.url.deletingLastPathComponent().appendingPathComponent("thumbnails"))

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Paths passed on the command line (`SiliconReader file.pdf`); AppKit
        // only forwards Finder/`open` requests through application(_:open:).
        for path in Self.documentArguments(CommandLine.arguments.dropFirst()) {
            open(URL(fileURLWithPath: path))
        }
        if windows.isEmpty && !openedAtLaunch {
            newHomeWindow()
        }
        NSApp.activate()

        // Debug hook: `-snapshot out.png` saves the first window once it has
        // finished rendering and quits. `-actions a,b` first sends those menu
        // actions (e.g. viewFacing,zoomFitWidth) to the document canvas.
        // Used for smoke checks without GUI automation.
        if let output = UserDefaults.standard.string(forKey: "snapshot") {
            let actions = UserDefaults.standard.string(forKey: "actions")?.split(separator: ",") ?? []
            for action in actions {
                let selector = Selector("\(action.trimmingCharacters(in: .whitespaces)):")
                guard let controller = windows.first, controller.perform(selector) else {
                    return finishSnapshot(error: "action \(action) was not handled")
                }
            }
            snapshotWhenSettled(to: URL(fileURLWithPath: output))
        }
    }

    /// Positional arguments; `-key value` pairs are NSUserDefaults overrides and are skipped.
    private static func documentArguments(_ args: ArraySlice<String>) -> [String] {
        var paths: [String] = []
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("-") {
                _ = iterator.next()
            } else {
                paths.append(arg)
            }
        }
        return paths
    }

    private func snapshotWhenSettled(to output: URL, timeout: Duration = .seconds(15)) {
        Task {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            while clock.now < deadline {
                guard let controller = windows.first else {
                    return finishSnapshot(error: "no window")
                }
                if controller.isSettled, thumbnails.isIdle, let png = controller.snapshotPNG() {
                    do {
                        try png.write(to: output)
                        return finishSnapshot(error: nil)
                    } catch {
                        return finishSnapshot(error: error.localizedDescription)
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            finishSnapshot(error: "pages did not finish rendering within \(timeout)")
        }
    }

    private func finishSnapshot(error: String?) {
        if let error {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
        NSApp.terminate(nil)
    }

    // MARK: - App lifecycle

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        urls.forEach { open($0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newHomeWindow() }
        return true
    }

    // MARK: - Windows

    private var keyController: MainWindowController? {
        NSApp.keyWindow?.windowController as? MainWindowController
    }

    @discardableResult
    private func makeWindow() -> MainWindowController {
        let isSnapshot = UserDefaults.standard.string(forKey: "snapshot") != nil
        let controller = MainWindowController(library: library, thumbnails: thumbnails, restoresFrame: !isSnapshot) {
            [weak self] url, window in
            self?.open(url, from: window)
        }
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        return controller
    }

    private func newHomeWindow() {
        makeWindow().showWindow(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        newHomeWindow()
    }

    @objc func openDocument(_ sender: Any?) {
        let requester = keyController
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        let djvu = ["djvu", "djv"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.pdf] + djvu
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { open($0, from: requester) }
    }

    /// Opens a document like SumatraPDF: an already open file gets focus, a
    /// home page is replaced in place, otherwise a new tab is added.
    private func open(_ url: URL, from requester: MainWindowController? = nil) {
        if let existing = windows.first(where: { $0.currentDocument?.engine.url == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let engine = openEngine(url) else { return }
        library.recordOpen(url.path)
        thumbnails.ensureThumbnail(for: engine)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let anchor = requester ?? keyController ?? windows.last
        if let anchor, anchor.isShowingHome {
            anchor.show(engine)
            anchor.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = makeWindow()
        controller.show(engine)
        if let anchorWindow = anchor?.window, let window = controller.window {
            anchorWindow.addTabbedWindow(window, ordered: .above)
        }
        controller.showWindow(nil)
    }

    /// Opens the engine, asking for a password as often as needed.
    private func openEngine(_ url: URL) -> (any DocumentEngine)? {
        var password: String?
        while true {
            do {
                return try DocumentOpener.open(url, password: password)
            } catch EngineError.passwordRequired(_), EngineError.wrongPassword(_) {
                guard let entered = askPassword(for: url, retry: password != nil) else { return nil }
                password = entered
            } catch {
                let alert = NSAlert()
                alert.messageText = "Cannot open document"
                alert.informativeText = String(describing: error)
                alert.runModal()
                return nil
            }
        }
    }

    private func askPassword(for url: URL, retry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = retry ? "Wrong password" : "Password required"
        alert.informativeText = "\(url.lastPathComponent) is protected. Enter the password to open it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
