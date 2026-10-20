import CoreGraphics
import Foundation

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard
            let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures")
        else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return url
    }

    static func temporaryFile(_ name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}

/// Generates PDFs with known geometry: each page has a solid red square in its
/// top-left quarter and is otherwise white.
enum TestPDF {
    static func make(pageSizes: [CGSize]) throws -> URL {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        for size in pageSizes {
            var box = CGRect(origin: .zero, size: size)
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            // PDF space is bottom-up, so the top-left quarter starts at half height.
            ctx.fill(CGRect(x: 0, y: size.height / 2, width: size.width / 2, height: size.height / 2))
            ctx.endPage()
        }
        ctx.closePDF()
        return try Fixtures.temporaryFile("generated.pdf", contents: data as Data)
    }
}

/// RGBA8 snapshot of a CGImage for pixel assertions.
struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.bytes = bytes
    }

    /// (r, g, b) at a top-down coordinate.
    func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
}
