/// Modifier keys of a shortcut.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// A physical key, independent of AppKit so the command table can be tested.
public enum Key: Hashable, Sendable {
    /// A printable key. Letters are stored lowercase; Shift is a modifier.
    /// Symbols that need Shift on a US layout ("?", "+") are stored as typed,
    /// without the Shift modifier.
    case character(Character)
    case up, down, left, right
    case pageUp, pageDown, home, end
    case space, enter, backspace, escape, tab
    case function(Int)
}

public struct Shortcut: Hashable, Sendable {
    public var key: Key
    public var modifiers: KeyModifiers

    public init(_ key: Key, _ modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Builds a normalized shortcut from what a key event reports, so lookups
    /// match the table regardless of how Shift was folded into the character.
    public static func fromEvent(characters: String, modifiers: KeyModifiers) -> Shortcut? {
        guard let first = characters.first, characters.count == 1 else { return nil }
        var modifiers = modifiers
        let key: Key
        switch first {
        case " ": key = .space
        case "\r", "\u{3}": key = .enter
        case "\u{7f}", "\u{8}": key = .backspace
        case "\u{1b}": key = .escape
        case "\t", "\u{19}": key = .tab
        default:
            if first.isLetter {
                if first.isUppercase { modifiers.insert(.shift) }
                key = .character(Character(first.lowercased()))
            } else {
                // The character already reflects Shift ("?" rather than "/").
                modifiers.remove(.shift)
                key = .character(first)
            }
        }
        return Shortcut(key, modifiers)
    }

    /// The character AppKit expects as a menu key equivalent, nil for keys
    /// that are not menu-friendly.
    public var menuKeyEquivalent: String? {
        switch key {
        case .character(let c): String(c)
        case .space: " "
        case .enter: "\r"
        case .backspace: "\u{8}"
        case .escape: "\u{1b}"
        case .tab: "\t"
        default: nil
        }
    }

    /// Human-readable form in macOS order: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case .character(let c): text += c.isLetter ? c.uppercased() : String(c)
        case .up: text += "↑"
        case .down: text += "↓"
        case .left: text += "←"
        case .right: text += "→"
        case .pageUp: text += "PgUp"
        case .pageDown: text += "PgDn"
        case .home: text += "Home"
        case .end: text += "End"
        case .space: text += "Space"
        case .enter: text += "Return"
        case .backspace: text += "⌫"
        case .escape: text += "Esc"
        case .tab: text += "Tab"
        case .function(let n): text += "F\(n)"
        }
        return text
    }

    /// Shortcuts with ⌘ or ⌃ are dispatched by the menu bar; the rest are
    /// handled by the document canvas so they never fire while typing.
    public var isMenuShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }
}
