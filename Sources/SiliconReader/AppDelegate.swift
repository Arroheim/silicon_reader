import AppKit
import ReaderCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [DocumentWindowController] = []
    private var openedAtLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Paths passed on the command line (`SiliconReader file.pdf`); AppKit
        // only forwards Finder/`open` requests through application(_:open:).
        for path in Self.documentArguments(CommandLine.arguments.dropFirst()) {
            open(URL(fileURLWithPath: path))
        }
        NSApp.activate()

        // Debug hook: `-snapshot out.png` saves the first window once it has
        // finished rendering and quits. Used for smoke checks without GUI automation.
        if let output = UserDefaults.standard.string(forKey: "snapshot") {
            snapshotWhenSettled(to: URL(fileURLWithPath: output))
        } else if windows.isEmpty && !openedAtLaunch {
            openDocument(nil)
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
                    return finishSnapshot(error: "no document window")
                }
                if controller.isSettled, let png = controller.snapshotPNG() {
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

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        let djvu = ["djvu", "djv"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.pdf] + djvu
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    private func open(_ url: URL) {
        do {
            let engine = try DocumentOpener.open(url)
            let controller = DocumentWindowController(engine: engine)
            controller.onClose = { [weak self, weak controller] in
                self?.windows.removeAll { $0 === controller }
            }
            windows.append(controller)
            controller.showWindow(nil)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot open document"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }
}
