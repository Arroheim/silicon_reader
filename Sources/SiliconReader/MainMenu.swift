import AppKit
import ReaderCore

/// The menu bar, built from `CommandTable` so menus, the canvas key handler
/// and keyboard help always agree.
@MainActor
enum MainMenu {
    /// Menu layout by command id; "-" is a separator.
    private static let layout: [(Command.Group, [String])] = [
        (
            .file,
            [
                "CmdNewWindow", "CmdDuplicateInNewWindow", "CmdOpenFile", "CmdReopenLastClosedFile", "-",
                "CmdOpenPrevFileInFolder", "CmdOpenNextFileInFolder", "-", "CmdSaveAs", "CmdReloadDocument", "-",
                "CmdClose", "CmdCloseCurrentDocument", "-", "CmdProperties", "CmdPrint",
            ]
        ),
        (
            .edit,
            [
                "std:undo", "std:redo", "-", "std:cut", "CmdCopySelection", "std:paste", "CmdSelectAll", "-",
                "CmdFindFirst", "CmdFindNext", "CmdFindPrev", "CmdFindMatchCase",
            ]
        ),
        (
            .view,
            [
                "CmdToggleBookmarks", "CmdToggleToolbar", "-", "CmdSinglePageView", "CmdFacingView", "CmdBookView",
                "CmdToggleContinuousView", "-", "CmdZoomFitPage", "CmdZoomActualSize", "CmdZoomFitWidth",
                "CmdZoomFitContent", "CmdZoomIn", "CmdZoomOut", "CmdZoomCustom", "CmdZoomToSelection",
                "CmdToggleZoom", "-",
                "CmdRotateLeft", "CmdRotateRight", "-", "CmdInvertColors", "CmdTogglePageInfo",
                "CmdToggleCursorPosition", "CmdToggleAutomaticallyScroll", "-", "CmdToggleFullscreen",
                "CmdTogglePresentationMode",
            ]
        ),
        (
            .go,
            [
                "CmdCommandPalette", "CmdNavigateTabs", "CmdNavigateHistory", "CmdNavigateFavorites",
                "CmdNavigateTableOfContents", "-", "CmdGoToNextPage", "CmdGoToPrevPage", "CmdGoToFirstPage",
                "CmdGoToLastPage", "CmdGoToPage", "-", "CmdNavigateBack", "CmdNavigateForward",
            ]
        ),
        (.favorites, ["CmdFavoriteAdd"]),
        (.window, ["CmdPrevTab", "CmdNextTab", "CmdMoveFrameFocus"]),
        (.help, ["CmdToggleKeyboardHelp"]),
    ]

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        for (group, ids) in layout {
            let menu = NSMenu(title: group.rawValue)
            if group == .window { addStandardWindowItems(to: menu) }
            for id in ids {
                if id == "-" {
                    menu.addItem(.separator())
                } else if let standard = standardItem(id) {
                    menu.addItem(standard)
                } else if let command = CommandTable.command(id: id) {
                    items(for: command).forEach(menu.addItem)
                }
            }
            main.addItem(submenu(menu))
            if group == .window { NSApp.windowsMenu = menu }
            if group == .help { NSApp.helpMenu = menu }
        }
        return main
    }

    /// A visible item for the command's first ⌘/⌃ shortcut plus hidden items
    /// for any other ⌘/⌃ alternates (e.g. ⌘= for ⌘+). Single-key shortcuts
    /// are not menu equivalents; the canvas handles them.
    private static func items(for command: Command) -> [NSMenuItem] {
        let action = Selector("\(command.action):")
        let menuShortcuts = command.shortcuts.filter(\.isMenuShortcut).filter { $0.menuKeyEquivalent != nil }
        let item = NSMenuItem(title: command.title, action: action, keyEquivalent: "")
        if let primary = menuShortcuts.first {
            apply(primary, to: item)
        } else if let single = command.shortcuts.first {
            // Show the single-key shortcut as a hint without making it an equivalent.
            item.toolTip = "Shortcut: \(single.display)"
        }
        let alternates = menuShortcuts.dropFirst().map { shortcut -> NSMenuItem in
            let hidden = NSMenuItem(title: command.title, action: action, keyEquivalent: "")
            apply(shortcut, to: hidden)
            hidden.isHidden = true
            hidden.allowsKeyEquivalentWhenHidden = true
            return hidden
        }
        return [item] + alternates
    }

    private static func apply(_ shortcut: Shortcut, to item: NSMenuItem) {
        item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
        // Arrow keys aren't characters in the table; map them for menus.
        switch shortcut.key {
        case .up: item.keyEquivalent = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .down: item.keyEquivalent = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case .left: item.keyEquivalent = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .right: item.keyEquivalent = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        default: break
        }
    }

    /// System text-editing items ("std:…") that text fields such as the search box rely on.
    private static func standardItem(_ id: String) -> NSMenuItem? {
        switch id {
        case "std:undo": return NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        case "std:redo":
            let item = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            item.keyEquivalentModifierMask = [.command, .shift]
            return item
        case "std:cut": return NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        case "std:paste": return NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        default: return nil
        }
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

    private static func addStandardWindowItems(to menu: NSMenu) {
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
    }
}
