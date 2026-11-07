// Writes a password-protected copy of a PDF, for manual testing:
//   swift scripts/make-password-pdf.swift <input.pdf> <output.pdf> <password>
import Foundation
import PDFKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: make-password-pdf.swift <input.pdf> <output.pdf> <password>")
    exit(64)
}
let password = arguments[3]
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    print("error: cannot open \(arguments[1])")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
guard document.write(to: output, withOptions: options) else {
    print("error: cannot write \(arguments[2])")
    exit(1)
}

// A file that opens without the password would make the check meaningless.
guard let check = PDFDocument(url: output), check.isLocked, !check.unlock(withPassword: password + "x"),
    check.unlock(withPassword: password)
else {
    print("error: \(arguments[2]) isn't protected as expected")
    exit(1)
}
print("ok \(arguments[2]): password \(password)")
