import Foundation
import Testing

@testable import ReaderCore

@Suite("Library")
struct LibraryTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("library.json")

    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    @Test("counts opens and remembers the last one")
    func recordOpen() {
        let library = Library(url: url)
        library.recordOpen("/a.pdf", at: date(1))
        library.recordOpen("/a.pdf", at: date(3))

        #expect(library.files == [FileRecord(path: "/a.pdf", openCount: 2, lastOpened: date(3))])
    }

    @Test("orders frequently read by open count, then recency")
    func frequentlyRead() {
        let library = Library(url: url)
        library.recordOpen("/once-old.pdf", at: date(1))
        library.recordOpen("/twice.pdf", at: date(2))
        library.recordOpen("/twice.pdf", at: date(3))
        library.recordOpen("/once-new.pdf", at: date(4))

        #expect(library.frequentlyRead(limit: 10).map(\.path) == ["/twice.pdf", "/once-new.pdf", "/once-old.pdf"])
        #expect(library.frequentlyRead(limit: 1).map(\.path) == ["/twice.pdf"])
        #expect(library.recent(limit: 2).map(\.path) == ["/once-new.pdf", "/twice.pdf"])
    }

    @Test("persists history and favorites across instances")
    func persistence() {
        let library = Library(url: url)
        library.recordOpen("/a.pdf", at: date(5))
        library.addFavorite(Favorite(path: "/a.pdf", page: 3, name: "Intro"))

        let reloaded = Library(url: url)

        #expect(reloaded.files == library.files)
        #expect(reloaded.favorites == [Favorite(path: "/a.pdf", page: 3, name: "Intro")])
    }

    @Test("starts empty when the file is corrupt")
    func corruptFile() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)

        #expect(Library(url: url).files.isEmpty)
    }

    @Test("renames an existing favorite instead of duplicating it")
    func favoriteRename() {
        let library = Library(url: url)
        library.addFavorite(Favorite(path: "/a.pdf", page: 3, name: "Old"))
        library.addFavorite(Favorite(path: "/a.pdf", page: 3, name: "New"))
        library.addFavorite(Favorite(path: "/a.pdf", page: 1, name: "First"))
        library.addFavorite(Favorite(path: "/b.pdf", page: 0, name: "Other"))

        #expect(library.favorites(for: "/a.pdf").map(\.name) == ["First", "New"])
        library.removeFavorite(path: "/a.pdf", page: 3)
        #expect(library.favorites(for: "/a.pdf").map(\.name) == ["First"])
    }

    @Test("forgetting a file drops its favorites too")
    func forget() {
        let library = Library(url: url)
        library.recordOpen("/a.pdf")
        library.addFavorite(Favorite(path: "/a.pdf", page: 0, name: "x"))

        library.forget("/a.pdf")

        #expect(library.files.isEmpty && library.favorites.isEmpty)
    }
}

@Suite("Navigation history")
struct NavigationHistoryTests {
    private func at(_ page: Int) -> DocumentPosition { DocumentPosition(page: page) }

    @Test("goes back and forward like a browser")
    func backForward() {
        var history = NavigationHistory()
        history.recordJump(from: at(1))  // 1 -> 5
        history.recordJump(from: at(5))  // 5 -> 9

        #expect(history.goBack(from: at(9)) == at(5))
        #expect(history.goBack(from: at(5)) == at(1))
        #expect(history.goBack(from: at(1)) == nil)
        #expect(history.goForward(from: at(1)) == at(5))
        #expect(history.goForward(from: at(5)) == at(9))
        #expect(!history.canGoForward)
    }

    @Test("a new jump clears the forward stack")
    func newJumpClearsForward() {
        var history = NavigationHistory()
        history.recordJump(from: at(1))
        _ = history.goBack(from: at(5))

        history.recordJump(from: at(1))

        #expect(!history.canGoForward)
        #expect(history.canGoBack)
    }

    @Test("ignores repeated jumps from the same place and caps its size")
    func dedupeAndLimit() {
        var history = NavigationHistory(limit: 3)
        for page in [1, 1, 2, 3, 4] { history.recordJump(from: at(page)) }

        #expect(history.goBack(from: at(9)) == at(4))
        #expect(history.goBack(from: at(4)) == at(3))
        #expect(history.goBack(from: at(3)) == at(2))
        #expect(history.goBack(from: at(2)) == nil)
    }
}

@Suite("Toolbar input")
struct UserInputTests {
    @Test(
        "parses page numbers and labels",
        arguments: [
            ("3", 2), (" 10 ", 9), ("0", nil), ("11", nil), ("abc", nil), ("", nil),
            ("iii", 2), ("A-1", 9),
        ] as [(String, Int?)])
    func page(text: String, expected: Int?) {
        let labels = [0: "i", 1: "ii", 2: "iii", 9: "A-1"]
        #expect(UserInput.page(text, pageCount: 10, label: { labels[$0] }) == expected)
    }

    @Test("prefers a matching label over the plain number")
    func labelWins() {
        // the seventh page is labelled "5"
        #expect(UserInput.page("5", pageCount: 10, label: { $0 == 6 ? "5" : nil }) == 6)
    }

    @Test(
        "parses zoom values and fit modes",
        arguments: [
            ("150", Zoom.percent(150)), ("150%", .percent(150)), ("66,67 %", .percent(66.67)),
            ("fit width", .fitWidth), ("Fit Page", .fitPage), ("1", .percent(8.33)), ("99999", .percent(6400)),
            ("", nil), ("abc", nil), ("-5", nil),
        ] as [(String, Zoom?)])
    func zoom(text: String, expected: Zoom?) {
        #expect(UserInput.zoom(text) == expected)
    }

    @Test(
        "formats zoom percentages",
        arguments: [(125.0, "125%"), (66.666, "66.67%"), (8.33, "8.33%"), (100.004, "100%")])
    func format(percent: CGFloat, expected: String) {
        #expect(UserInput.format(percent: percent) == expected)
    }
}
