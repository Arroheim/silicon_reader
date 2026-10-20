import CoreGraphics
import Foundation

/// Builds a CGImage from a top-down 8-bit gray or RGB buffer, copying the pixels.
func makeImage(width: Int, height: Int, stride: Int, components: Int, pixels: UnsafeRawPointer) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let data = Data(bytes: pixels, count: stride * height)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    let colorSpace = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8 * components,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
}
