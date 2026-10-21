import AppKit
import ReaderCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [MainWindowController] = []
    private var openedAtLaunch = false

    /// Debug runs (`-snapshot`, `-control`) neither write per-file state nor
    /// save/restore the session, so each run starts from the same place.
    /// `-persist YES` turns both back on to test them.
    private let isSnapshot = ["snapshot", "control"].contains { UserDefaults.standard.string(forKey: $0) != nil }
    private var controlServer: ControlServer?

    var thumbnailsIdle: Bool { thumbnails.isIdle }
    private var persists: Bool { !isSnapshot || UserDefaults.standard.bool(forKey: "persist") }

    /// `-library path.json` points the app at another library (tests, smoke runs)
    /// so they never touch the user's history.
    private let library = Library(
        url: UserDefaults.standard.string(forKey: "library").map { URL(fileURLWithPath: $0) } ?? Library.defaultURL)
    private lazy var thumbnails = ThumbnailStore(
        directory: library.url.deletingLastPathComponent().appendingPathComponent("thumbnails"))

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(recentMenuDelegate: recentMenu)
    }

    private lazy var recentMenu = RecentMenuDelegate(app: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Paths passed on the command line (`SiliconReader file.pdf`); AppKit
        // only forwards Finder/`open` requests through application(_:open:).
        for path in Self.documentArguments(CommandLine.arguments.dropFirst()) {
            openFile(URL(fileURLWithPath: path))
        }
        let restores = persists && library.settings.restoreSession
        if windows.isEmpty && !openedAtLaunch && !(restores && restoreSession()) {
            newHomeWindow()
        }
        NSApp.activate()

        // Debug control channel for e2e tests: `-control /path/to/socket`.
        if let path = UserDefaults.standard.string(forKey: "control") {
            let server = ControlServer(path: path) { request in await self.handleControl(request) }
            do {
                try server.start()
                controlServer = server
            } catch {
                FileHandle.standardError.write(Data("control channel failed: \(error)\n".utf8))
                exit(2)
            }
        }

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
            // `-find text` searches after the actions; the snapshot waits for the result.
            if let query = UserDefaults.standard.string(forKey: "find") {
                guard let canvas = windows.first?.canvas else { return finishSnapshot(error: "-find needs a document") }
                canvas.find(query, forward: true)
            }
            // `-printToPDF out.pdf` prints the document through the print path into a file.
            if let path = UserDefaults.standard.string(forKey: "printToPDF") {
                guard let controller = windows.first, let engine = controller.currentDocument?.engine,
                    let window = controller.window
                else { return finishSnapshot(error: "-printToPDF needs a document") }
                let title = engine.url.lastPathComponent
                PrintView.run(engine: engine, title: title, for: window, saveTo: URL(fileURLWithPath: path))
            }
            // `-palette text` opens the command palette filtered by `text`.
            if let text = UserDefaults.standard.string(forKey: "palette") {
                windows.first?.showPalette(nil, text: text)
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

    /// `-snapshotAfter seconds` waits at least that long first, e.g. to change
    /// the open file and see the app reload it.
    private func snapshotWhenSettled(to output: URL, timeout: Duration = .seconds(15)) {
        let minimumWait = Duration.seconds(UserDefaults.standard.double(forKey: "snapshotAfter"))
        Task {
            let clock = ContinuousClock()
            let earliest = clock.now + minimumWait
            let deadline = earliest + timeout
            try? await Task.sleep(until: earliest)
            while clock.now < deadline {
                guard let controller = windows.first else {
                    return finishSnapshot(error: "no window")
                }
                if controller.isSettled, thumbnails.isIdle, let png = Self.snapshotTarget(controller) {
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

    /// `-snapshotWindow palette|properties|settings|about` captures that window instead of the document window.
    private static func snapshotTarget(_ controller: MainWindowController) -> Data? {
        let window: NSWindow? =
            switch UserDefaults.standard.string(forKey: "snapshotWindow") {
            case "palette": NSApp.windows.first { $0 is PalettePanel && $0.isVisible }
            case "properties": NSApp.windows.first { $0.title == "Document Properties" && $0.isVisible }
            case "settings": NSApp.windows.first { $0.title == "Settings" && $0.isVisible }
            // AppKit's standard About panel has no public class or title.
            case "about": NSApp.windows.first { !($0.windowController is MainWindowController) && $0.isVisible }
            default: controller.window
            }
        guard let view = window?.contentView?.superview ?? window?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
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
        urls.forEach { openFile($0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard persists else { return }
        windows.forEach { $0.saveDocumentState() }
        library.saveSession(currentSession())
    }

    // MARK: - Session

    /// Windows in front-to-back order, each with its tabs in tab-bar order.
    private func currentSession() -> Session {
        var seen = Set<ObjectIdentifier>()
        var result: [Session.Window] = []
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? MainWindowController }
        for controller in ordered + windows {
            guard let window = controller.window, !seen.contains(ObjectIdentifier(window)) else { continue }
            let group = window.tabbedWindows ?? [window]
            group.forEach { seen.insert(ObjectIdentifier($0)) }
            let controllers = group.compactMap { $0.windowController as? MainWindowController }
            let tabs = controllers.compactMap { $0.documentURL?.path }
            guard !tabs.isEmpty else { continue }
            let selectedPath = (window.tabGroup?.selectedWindow?.windowController as? MainWindowController)?
                .documentURL?.path
            let selected = selectedPath.flatMap { tabs.firstIndex(of: $0) } ?? 0
            result.append(Session.Window(tabs: tabs, selectedTab: selected))
        }
        return Session(windows: result)
    }

    /// Reopens the last session's windows and tabs; false if there was nothing to restore.
    private func restoreSession() -> Bool {
        guard let session = library.session?.filtered(exists: { FileManager.default.fileExists(atPath: $0) }),
            !session.windows.isEmpty
        else { return false }

        var restoredAny = false
        for saved in session.windows {
            var tabs: [MainWindowController] = []
            for path in saved.tabs {
                guard let engine = openEngine(URL(fileURLWithPath: path)) else { continue }
                let controller = makeWindow()
                controller.show(engine, countsAsOpen: false)
                if let first = tabs.first?.window, let window = controller.window {
                    first.addTabbedWindow(window, ordered: .above)
                }
                controller.showWindow(nil)
                tabs.append(controller)
            }
            let selected = tabs.indices.contains(saved.selectedTab) ? tabs[saved.selectedTab] : tabs.first
            selected?.window?.makeKeyAndOrderFront(nil)
            restoredAny = restoredAny || !tabs.isEmpty
        }
        return restoredAny
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
        let controller = MainWindowController(
            library: library, thumbnails: thumbnails, host: self, restoresFrame: !isSnapshot, persistsState: persists)
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
        // Debug runs: `-openPanelResult path` stands in for the user's pick, so
        // e2e tests can go through Open… without a modal panel.
        if isSnapshot, let path = UserDefaults.standard.string(forKey: "openPanelResult") {
            openFile(URL(fileURLWithPath: path), from: requester)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        let djvu = ["djvu", "djv"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.pdf] + djvu
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { openFile($0, from: requester) }
    }

    /// Recently closed documents, newest last (SumatraPDF's Reopen Last Closed).
    private var closedDocuments: [URL] = []

    @objc func reopenLastClosed(_ sender: Any?) {
        let openURLs = Set(windows.compactMap(\.documentURL))
        while let url = closedDocuments.popLast() {
            if !openURLs.contains(url) && FileManager.default.fileExists(atPath: url.path) {
                openFile(url)
                return
            }
        }
        NSSound.beep()
    }

    private var keyboardHelp: KeyboardHelpWindowController?

    @objc func showKeyboardHelp(_ sender: Any?) {
        let help = keyboardHelp ?? KeyboardHelpWindowController()
        keyboardHelp = help
        help.showWindow(nil)
    }

    private(set) var settingsWindow: SettingsWindowController?

    @objc func showSettings(_ sender: Any?) {
        let settings = settingsWindow ?? SettingsWindowController(library: library)
        settingsWindow = settings
        settings.showWindow(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: AboutCredits.text()])
    }

    // MARK: - Open Recent

    /// Number of files listed in File ▸ Open Recent.
    static let recentLimit = 15

    /// Existing files from the history, newest first.
    var recentDocuments: [URL] {
        library.recent(limit: Self.recentLimit * 2)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(Self.recentLimit)
            .map { URL(fileURLWithPath: $0.path) }
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openFile(url)
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        library.clearRecent()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    /// Opens a document like SumatraPDF: an already open file gets focus, a
    /// home page is replaced in place, otherwise a new tab is added.
    @discardableResult
    private func openFile(_ url: URL, from requester: MainWindowController? = nil) -> MainWindowController? {
        if let existing = windows.first(where: { $0.documentURL == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }
        guard let engine = openEngine(url) else { return nil }

        let anchor = requester ?? keyController ?? windows.last
        if let anchor, anchor.isShowingHome {
            anchor.show(engine)
            anchor.window?.makeKeyAndOrderFront(nil)
            return anchor
        }
        let controller = makeWindow()
        controller.show(engine)
        if let anchorWindow = anchor?.window, let window = controller.window {
            anchorWindow.addTabbedWindow(window, ordered: .above)
        }
        controller.showWindow(nil)
        return controller
    }

    /// Opens the engine, asking for a password as often as needed.
    func openEngine(_ url: URL) -> (any DocumentEngine)? {
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

extension AppDelegate: MainWindowHost {
    func open(_ url: URL, from window: MainWindowController) -> MainWindowController? {
        openFile(url, from: window)
    }

    /// Duplicate in New Window: a separate window (not a tab) on the same place.
    func openInNewWindow(_ url: URL, state: ViewState) {
        guard let engine = openEngine(url) else { return }
        let controller = makeWindow()
        controller.window?.tabbingMode = .disallowed
        controller.show(engine, state: state)
        controller.window?.tabbingMode = .preferred
        if let frame = keyController?.window?.frame {
            controller.window?.setFrameOrigin(NSPoint(x: frame.minX + 24, y: frame.minY - 24))
        }
        controller.showWindow(nil)
    }

    func documentDidClose(_ url: URL) {
        closedDocuments.removeAll { $0 == url }
        closedDocuments.append(url)
    }

    func documentDidOpen(_ engine: any DocumentEngine, countsAsOpen: Bool) {
        if countsAsOpen {
            library.recordOpen(engine.url.path)
            NSDocumentController.shared.noteNewRecentDocumentURL(engine.url)
        }
        thumbnails.ensureThumbnail(for: engine)
        closedDocuments.removeAll { $0 == engine.url }
    }
}
