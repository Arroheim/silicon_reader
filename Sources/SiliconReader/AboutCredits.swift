import AppKit

/// The credits shown in About Silicon Reader: the author, then the projects
/// the app is built on and their licenses.
enum AboutCredits {
    static let author = "Stanislav Seredkin aka Itterheim aka Arronax"
    static let email = "abigor.int3h@gmail.com"
    static let repository = "https://github.com/Arroheim/silicon_reader"

    @MainActor
    static func text() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let secondary = body.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }

        let result = NSMutableAttributedString()
        func add(_ text: String, _ attributes: [NSAttributedString.Key: Any], link: String? = nil) {
            var attributes = attributes
            if let link { attributes[.link] = URL(string: link) }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        add("by \(author)\n", body)
        add(email, body, link: "mailto:\(email)")
        add("\n", body)
        add("github.com/Arroheim/silicon_reader", body, link: repository)
        add("\n\n", body)
        add("In the spirit of SumatraPDF. Built on MuPDF\n", secondary)
        add("and djvudec. License: AGPL-3.0.", secondary)
        return result
    }
}
