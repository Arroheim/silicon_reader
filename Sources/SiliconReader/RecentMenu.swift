import AppKit

/// Fills File ▸ Open Recent from the library's history when it opens, so it
/// always matches the home page's list (the app has no NSDocument types for
/// AppKit's own recent-documents menu to manage).
@MainActor
final class RecentMenuDelegate: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        Self.fill(menu, with: app.recentDocuments, target: app)
    }

    /// One item per file (title = file name, folder in the tooltip), then Clear Menu.
    static func fill(_ menu: NSMenu, with urls: [URL], target: AppDelegate) {
        menu.removeAllItems()
        for url in urls {
            let item = NSMenuItem(
                title: url.lastPathComponent, action: #selector(AppDelegate.openRecentDocument(_:)),
                keyEquivalent: "")
            item.target = target
            item.representedObject = url
            item.toolTip = url.deletingLastPathComponent().path
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(
            title: "Clear Menu", action: #selector(AppDelegate.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = target
        // Without an action the item shows disabled, as Clear Menu does on an empty list.
        if urls.isEmpty { clear.action = nil }
        menu.addItem(clear)
    }
}
