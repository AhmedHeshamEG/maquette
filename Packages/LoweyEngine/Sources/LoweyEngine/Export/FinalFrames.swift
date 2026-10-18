import Accelerate
import CoreGraphics
import CoreVideo
import Foundation
import LoweyCore

/// Final (A1): what the live preview can't afford, for exports. Each frame is the average of several moments across
/// half a frame (a 180° shutter: motion blur), each drawn larger than the file and brought down with a high-quality
/// filter (anti-aliasing past the preview's); the session draws with the best shadows and the finest water.
public enum FinalFrames {
    /// Moments a frame averages.
    static let samples = 8
    /// The shutter, as a share of the frame's time.
    static let shutter = 0.5

    /// The moments that make the frame at `time`, centred on it.
    public static func moments(at time: Double, fps: Int) -> [Double] {
        let span = shutter / Double(max(fps, 1))
        return (0 ..< samples).map { time - span / 2 + span * (Double($0) + 0.5) / Double(samples) }
    }

    /// How much larger each moment is drawn: twice for HD, the file's own size from 4K up (where the pixels are small
    /// enough already and twice would be past what an iPad's GPU takes).
    public static func supersample(longSide: Int) -> Int {
        longSide * 2 <= 4096 ? 2 : 1
    }

    /// BGRA brought down from `width` × `height` to `outWidth` × `outHeight` (a high-quality Lanczos filter).
    static func downsampled(_ bytes: [UInt8], width: Int, height: Int, to outWidth: Int, _ outHeight: Int) -> [UInt8] {
        guard width != outWidth || height != outHeight else { return bytes }
        var source = bytes
        var result = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        source.withUnsafeMutableBytes { input in
            result.withUnsafeMutableBytes { output in
                var from = vImage_Buffer(data: input.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                var to = vImage_Buffer(data: output.baseAddress, height: vImagePixelCount(outHeight), width: vImagePixelCount(outWidth),
                                       rowBytes: outWidth * 4)
                _ = vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return result
    }

    /// Adds BGRA bytes to a running sum.
    static func accumulate(_ bytes: [UInt8], into sum: inout [Float]) {
        var values = [Float](repeating: 0, count: bytes.count)
        vDSP_vfltu8(bytes, 1, &values, 1, vDSP_Length(bytes.count))
        sum.withUnsafeMutableBufferPointer { total in
            guard let base = total.baseAddress else { return }
            vDSP_vadd(base, 1, values, 1, base, 1, vDSP_Length(bytes.count))
        }
    }

    /// The average of `count` frames summed.
    static func average(_ sum: [Float], count: Int) -> [UInt8] {
        var divisor = Float(max(count, 1))
        var mean = [Float](repeating: 0, count: sum.count)
        vDSP_vsdiv(sum, 1, &divisor, &mean, 1, vDSP_Length(sum.count))
        var result = [UInt8](repeating: 0, count: sum.count)
        vDSP_vfixru8(mean, 1, &result, 1, vDSP_Length(sum.count))
        return result
    }

    /// Copies BGRA rows (top row first) into a pixel buffer of the same size.
    static func copy(_ bytes: [UInt8], width: Int, height: Int, into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height
        else { throw RenderError.readback }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        bytes.withUnsafeBytes { source in
            guard let start = source.baseAddress else { return }
            for row in 0 ..< height {
                (base + row * stride).copyMemory(from: start + row * width * 4, byteCount: width * 4)
            }
        }
    }
}

public extension PreviewQuality {
    /// Final exports: the sun's shadow map at twice the full preview's.
    static let final: PreviewQuality = {
        var quality = PreviewQuality(tier: .a)
        quality.shadowMapSize = 4096
        return quality
    }()
}
