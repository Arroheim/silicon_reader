// Writes a scan-like PDF: every page is a full-page JPEG of its own, repeating the
// given images, for manual tests with heavy documents. JPEGs go in unchanged.
//   swift scripts/make-image-pdf.swift <output.pdf> <pages> <width> <height> <image.jpg>...
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 5, let pages = Int(arguments[2]), let width = Int(arguments[3]), let height = Int(arguments[4])
else {
    print("usage: make-image-pdf.swift <output.pdf> <pages> <width> <height> <image.jpg>...")
    exit(64)
}
let images = try arguments[5...].map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
let path = arguments[1]
guard FileManager.default.createFile(atPath: path, contents: nil), let out = FileHandle(forWritingAtPath: path) else {
    print("error: cannot write \(path)")
    exit(1)
}

var position = 0
var offsets: [Int: Int] = [:]

func write(_ data: Data) throws {
    try out.write(contentsOf: data)
    position += data.count
}

func write(_ text: String) throws {
    try write(Data(text.utf8))
}

/// Objects 1 and 2 are the catalog and page tree; each page then takes three.
func object(_ number: Int, _ body: String) throws {
    offsets[number] = position
    try write("\(number) 0 obj\n\(body)\nendobj\n")
}

try write("%PDF-1.4\n")
try object(1, "<< /Type /Catalog /Pages 2 0 R >>")
let kids = (0..<pages).map { "\(3 + $0 * 3) 0 R" }.joined(separator: " ")
try object(2, "<< /Type /Pages /Count \(pages) /Kids [\(kids)] >>")

let contents = Data("q 612 0 0 792 0 0 cm /Scan Do Q".utf8)
for page in 0..<pages {
    let first = 3 + page * 3
    try object(
        first,
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents \(first + 1) 0 R "
            + "/Resources << /XObject << /Scan \(first + 2) 0 R >> >> >>")
    try object(
        first + 1,
        "<< /Length \(contents.count) >>\nstream\n" + String(decoding: contents, as: UTF8.self) + "\nendstream")

    let image = images[page % images.count]
    offsets[first + 2] = position
    try write(
        "\(first + 2) 0 obj\n<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) "
            + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length \(image.count) >>\nstream\n")
    try write(image)
    try write("\nendstream\nendobj\n")
}

let count = 3 + pages * 3
let xref = position
var table = "xref\n0 \(count)\n0000000000 65535 f \n"
for number in 1..<count {
    table += String(format: "%010d 00000 n \n", offsets[number] ?? 0)
}
try write(table + "trailer\n<< /Size \(count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
try out.close()
print("ok \(path): \(pages) pages, \(position / 1_048_576) MB")
