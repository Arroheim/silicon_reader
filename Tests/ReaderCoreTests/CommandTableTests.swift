import Foundation
import Testing

@testable import ReaderCore

@Suite("Command table")
struct CommandTableTests {
    @Test("no shortcut is bound to two commands")
    func uniqueShortcuts() {
        var seen: [Shortcut: String] = [:]
        for command in CommandTable.all {
            for shortcut in command.shortcuts {
                let previous = seen[shortcut] ?? ""
                #expect(seen[shortcut] == nil, "\(shortcut.display) is used by \(previous) and \(command.id)")
                seen[shortcut] = command.id
            }
        }
    }

    @Test("command ids and actions are unique")
    func uniqueIDs() {
        #expect(Set(CommandTable.all.map(\.id)).count == CommandTable.all.count)
        #expect(Set(CommandTable.all.map(\.action)).count == CommandTable.all.count)
    }

    @Test("shortcuts are stored the way key events normalize them")
    func normalized() {
        for command in CommandTable.all {
            for shortcut in command.shortcuts {
                guard case .character(let c) = shortcut.key else { continue }
                if c.isLetter {
                    #expect(c.isLowercase, "\(command.id): letters are lowercase, Shift is a modifier")
                } else {
                    #expect(!shortcut.modifiers.contains(.shift), "\(command.id): \(c) already implies Shift")
                }
            }
        }
    }

    @Test(
        "SumatraPDF's single-key shortcuts are all present",
        arguments: ["j", "k", "h", "l", "n", "p", "c", "z", "f", "g", "i", "m", "q", "r", "w", ".", "[", "]", "?"])
    func sumatraKeys(key: Character) {
        #expect(CommandTable.command(for: Shortcut(.character(key))) != nil)
    }

    @Test("menu shortcuts are the ones with ⌘ or ⌃")
    func menuShortcuts() {
        #expect(Shortcut(.character("n"), .command).isMenuShortcut)
        #expect(Shortcut(.character("s"), [.control, .command]).isMenuShortcut)
        #expect(!Shortcut(.character("n")).isMenuShortcut)
        #expect(!Shortcut(.down, .shift).isMenuShortcut)
    }
}

@Suite("Shortcut")
struct ShortcutTests {
    @Test(
        "normalizes key events",
        arguments: [
            ("j", [], Shortcut(.character("j"))),
            ("I", .shift, Shortcut(.character("i"), .shift)),
            ("I", [], Shortcut(.character("i"), .shift)),
            ("?", .shift, Shortcut(.character("?"))),
            (" ", .shift, Shortcut(.space, .shift)),
            ("\r", [], Shortcut(.enter)),
            ("\u{7f}", .shift, Shortcut(.backspace, .shift)),
            ("n", [.shift, .command], Shortcut(.character("n"), [.shift, .command])),
        ] as [(String, KeyModifiers, Shortcut)])
    func fromEvent(characters: String, modifiers: KeyModifiers, expected: Shortcut) {
        #expect(Shortcut.fromEvent(characters: characters, modifiers: modifiers) == expected)
    }

    @Test(
        "displays in macOS order",
        arguments: [
            (Shortcut(.character("f"), [.shift, .command]), "⇧⌘F"),
            (Shortcut(.character("s"), [.control, .command]), "⌃⌘S"),
            (Shortcut(.character("g"), [.option, .command]), "⌥⌘G"),
            (Shortcut(.down, .option), "⌥↓"),
            (Shortcut(.function(12)), "F12"),
            (Shortcut(.character("?")), "?"),
        ])
    func display(shortcut: Shortcut, expected: String) {
        #expect(shortcut.display == expected)
    }
}

@Suite("Folder navigation")
struct FolderNavigationTests {
    private func makeFolder(_ names: [String]) throws -> (URL, [URL]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = try names.map { name -> URL in
            let url = dir.appendingPathComponent(name)
            try Data().write(to: url)
            return url
        }
        return (dir, urls)
    }

    @Test("walks files in Finder order and skips other types")
    func order() throws {
        let (dir, _) = try makeFolder(["b10.pdf", "b2.pdf", "notes.txt", "a.djvu", "C.PDF"])
        let b2 = dir.appendingPathComponent("b2.pdf")

        #expect(FolderNavigation.sibling(of: b2, forward: true)?.lastPathComponent == "b10.pdf")
        #expect(FolderNavigation.sibling(of: b2, forward: false)?.lastPathComponent == "a.djvu")
        #expect(
            FolderNavigation.sibling(of: dir.appendingPathComponent("b10.pdf"), forward: true)?.lastPathComponent
                == "C.PDF")
    }

    @Test("does not wrap around at the ends")
    func noWrap() throws {
        let (dir, _) = try makeFolder(["a.pdf", "b.pdf"])

        #expect(FolderNavigation.sibling(of: dir.appendingPathComponent("b.pdf"), forward: true) == nil)
        #expect(FolderNavigation.sibling(of: dir.appendingPathComponent("a.pdf"), forward: false) == nil)
    }

    @Test("skips files that no longer exist")
    func skipsMissing() throws {
        let (dir, urls) = try makeFolder(["a.pdf", "b.pdf", "c.pdf"])
        try FileManager.default.removeItem(at: urls[1])

        let next = FolderNavigation.sibling(of: urls[0], in: urls, forward: true)

        #expect(next?.lastPathComponent == "c.pdf")
        _ = dir
    }
}
