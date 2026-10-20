import AppKit
import ReaderCore

/// SumatraPDF's keyboard help ("?"): every command and its shortcuts, straight
/// from `CommandTable`.
@MainActor
final class KeyboardHelpWindowController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false)
        panel.title = "Keyboard Shortcuts"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true

        let text = NSTextView()
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.textStorage?.setAttributedString(Self.content())
        text.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        panel.contentView = scroll
        panel.center()
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func content() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 260)]
        paragraph.paragraphSpacing = 2
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let keys: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]
        let header: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor,
        ]

        for group in Command.Group.allCases {
            let commands = CommandTable.commands(in: group).filter { !$0.shortcuts.isEmpty }
            guard !commands.isEmpty else { continue }
            let title = (result.length > 0 ? "\n" : "") + group.rawValue + "\n"
            result.append(NSAttributedString(string: title, attributes: header))
            for command in commands {
                result.append(NSAttributedString(string: command.title + "\t", attributes: body))
                result.append(
                    NSAttributedString(
                        string: command.shortcuts.map(\.display).joined(separator: ", ") + "\n", attributes: keys))
            }
        }
        return result
    }
}
