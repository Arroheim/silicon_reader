import AppKit

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(goMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    /// Shortcuts follow SumatraPDF's table (src/shared/Accelerators.cpp) with
    /// Ctrl mapped to ⌘, plus its macOS-specific overrides (⌘0 actual size, ⌘9 fit page).
    /// Single-letter shortcuts (c, z, n, p, [, ]) are handled by the canvas so
    /// they never fire while typing in a text field.
    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Single Page", action: #selector(DocumentView.viewSinglePage(_:)), keyEquivalent: "6")
        menu.addItem(withTitle: "Facing", action: #selector(DocumentView.viewFacing(_:)), keyEquivalent: "7")
        menu.addItem(withTitle: "Book View", action: #selector(DocumentView.viewBook(_:)), keyEquivalent: "8")
        menu.addItem(withTitle: "Continuous", action: #selector(DocumentView.toggleContinuous(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Fit Page", action: #selector(DocumentView.zoomFitPage(_:)), keyEquivalent: "9")
        menu.addItem(withTitle: "Actual Size", action: #selector(DocumentView.zoomActualSize(_:)), keyEquivalent: "0")
        menu.addItem(withTitle: "Fit Width", action: #selector(DocumentView.zoomFitWidth(_:)), keyEquivalent: "2")
        menu.addItem(withTitle: "Fit Content", action: #selector(DocumentView.zoomFitContent(_:)), keyEquivalent: "3")
        menu.addItem(withTitle: "Zoom In", action: #selector(DocumentView.zoomIn(_:)), keyEquivalent: "+")
        menu.addItem(hidden("Zoom In", action: #selector(DocumentView.zoomIn(_:)), key: "="))
        menu.addItem(withTitle: "Zoom Out", action: #selector(DocumentView.zoomOut(_:)), keyEquivalent: "-")
        menu.addItem(withTitle: "Toggle Zoom", action: #selector(DocumentView.toggleZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let left = menu.addItem(
            withTitle: "Rotate Left", action: #selector(DocumentView.rotateLeft(_:)), keyEquivalent: "-")
        left.keyEquivalentModifierMask = [.command, .shift]
        let right = menu.addItem(
            withTitle: "Rotate Right", action: #selector(DocumentView.rotateRight(_:)), keyEquivalent: "+")
        right.keyEquivalentModifierMask = [.command, .shift]
        let rightAlt = hidden("Rotate Right", action: #selector(DocumentView.rotateRight(_:)), key: "=")
        rightAlt.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(rightAlt)
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        menu.addItem(withTitle: "Next Page", action: #selector(DocumentView.goToNextPage(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Previous Page", action: #selector(DocumentView.goToPreviousPage(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "First Page", action: #selector(DocumentView.goToFirstPage(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        menu.addItem(
            withTitle: "Last Page", action: #selector(DocumentView.goToLastPage(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        return menu
    }

    /// A menu item that only provides an extra key equivalent (e.g. ⌘= for ⌘+).
    private static func hidden(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        return menu
    }
}
