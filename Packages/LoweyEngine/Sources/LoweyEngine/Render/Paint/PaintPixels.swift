import CoreGraphics
import Foundation
import ImageIO
import LoweyCore

/// Pixels between PNG tiles, RGBA pictures and the GPU's premultiplied layers.
public enum PaintPixels {
    static let side = PaintSurface.tileSize

    /// A tile's PNG as premultiplied RGBA8 (the colours as stored, no colour conversion).
    static func premultiplied(png: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
    }

    static func premultiplied(image: RGBAImage) -> [UInt8] {
        var bytes = image.pixels
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = UInt16(bytes[index + 3])
            guard alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                bytes[index + channel] = UInt8((UInt16(bytes[index + channel]) * alpha + 127) / 255)
            }
        }
        return bytes
    }

    /// Premultiplied bytes back to a straight-alpha picture.
    static func straight(_ bytes: [UInt8], width: Int, height: Int) -> RGBAImage {
        var pixels = bytes
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                pixels[index + channel] = UInt8(min((Int(pixels[index + channel]) * 255 + alpha / 2) / alpha, 255))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// A tile's PNG for the project, compressed (ImageIO).
    public static func png(_ image: RGBAImage) -> Data {
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4,
                                    space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return PNGCodec.encode(image) }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : PNGCodec.encode(image)
    }

    /// Any picture ImageIO reads (PNG, JPEG, HEIC…) as straight RGBA, as stored (no colour conversion): imported
    /// material pictures and decals.
    public static func decode(_ data: Data) -> RGBAImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? straight(bytes, width: width, height: height) : nil
    }
}
