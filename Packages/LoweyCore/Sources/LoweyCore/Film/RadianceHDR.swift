import Foundation

/// A Radiance `.hdr` picture (RGBE, flat or run-length scanlines), the format HDRI sky and studio maps come in. Read in
/// pure Swift (F1), shrunk as it's read: a 16k map never sits in memory whole.
public struct RadianceHDR: Sendable {
    public let width: Int
    public let height: Int
    /// Linear RGB, row by row from the top, three floats a pixel.
    public let pixels: [Float]

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notRadiance
        case badSize
        case truncated

        public var description: String {
            switch self {
            case .notRadiance: "That isn't a Radiance .hdr picture."
            case .badSize: "The picture's size line can't be read."
            case .truncated: "The picture ends early."
            }
        }
    }

    public init(width: Int, height: Int, pixels: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Reads `data`, averaging it down so it is at most `maxWidth` wide (the height follows: an HDRI is 2:1).
    public static func read(_ data: Data, maxWidth: Int = 2048) throws(Failure) -> RadianceHDR {
        let bytes = [UInt8](data)
        var cursor = 0
        func line() -> String? {
            guard cursor < bytes.count else { return nil }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0x0A {
                cursor += 1
            }
            let text = String(decoding: bytes[start ..< cursor], as: UTF8.self)
            cursor += 1
            return text
        }
        guard let magic = line(), magic.hasPrefix("#?") else { throw .notRadiance }
        while let header = line(), !header.isEmpty {
            if header.hasPrefix("FORMAT="), header != "FORMAT=32-bit_rle_rgbe" { throw .notRadiance }
        }
        let size = (line() ?? "").split(separator: " ")
        guard size.count == 4, size[0] == "-Y", size[2] == "+X", let height = Int(size[1]), let width = Int(size[3]), width > 0, height > 0,
              width <= 65536, height <= 32768 else { throw .badSize }
        let factor = max(1, Int((Double(width) / Double(maxWidth)).rounded(.up)))
        let outWidth = max(width / factor, 1)
        let outHeight = max(height / factor, 1)
        var sums = [Float](repeating: 0, count: outWidth * outHeight * 3)
        var scanline = [UInt8](repeating: 0, count: width * 4)
        for row in 0 ..< height {
            try readScanline(bytes, &cursor, width: width, into: &scanline)
            let outRow = min(row / factor, outHeight - 1)
            for column in 0 ..< width {
                let exponent = scanline[column * 4 + 3]
                guard exponent != 0 else { continue }
                let scale = Float(sign: .plus, exponent: Int(exponent) - 136, significand: 1)
                let out = (outRow * outWidth + min(column / factor, outWidth - 1)) * 3
                // Each byte stands for the middle of its step (Radiance's own decoding).
                sums[out] += (Float(scanline[column * 4]) + 0.5) * scale
                sums[out + 1] += (Float(scanline[column * 4 + 1]) + 0.5) * scale
                sums[out + 2] += (Float(scanline[column * 4 + 2]) + 0.5) * scale
            }
        }
        let share = 1 / Float(factor * factor)
        return RadianceHDR(width: outWidth, height: outHeight, pixels: sums.map { $0 * share })
    }

    /// One scanline into RGBE bytes: the new run-length form (2, 2, width) or flat.
    private static func readScanline(_ bytes: [UInt8], _ cursor: inout Int, width: Int, into line: inout [UInt8]) throws(Failure) {
        guard cursor + 4 <= bytes.count else { throw .truncated }
        let isRLE = width >= 8 && width < 32768 && bytes[cursor] == 2 && bytes[cursor + 1] == 2
            && (Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])) == width
        guard isRLE else {
            guard cursor + width * 4 <= bytes.count else { throw .truncated }
            for index in 0 ..< width * 4 {
                line[index] = bytes[cursor + index]
            }
            cursor += width * 4
            return
        }
        cursor += 4
        for channel in 0 ..< 4 {
            var column = 0
            while column < width {
                guard cursor < bytes.count else { throw .truncated }
                var count = Int(bytes[cursor])
                cursor += 1
                if count > 128 {
                    count -= 128
                    guard cursor < bytes.count, column + count <= width else { throw .truncated }
                    let value = bytes[cursor]
                    cursor += 1
                    for offset in 0 ..< count {
                        line[(column + offset) * 4 + channel] = value
                    }
                } else {
                    guard count > 0, cursor + count <= bytes.count, column + count <= width else { throw .truncated }
                    for offset in 0 ..< count {
                        line[(column + offset) * 4 + channel] = bytes[cursor + offset]
                    }
                    cursor += count
                }
                column += count
            }
        }
    }

    /// A flat-written `.hdr` of linear RGB (tests, and handing a picture back).
    public static func write(width: Int, height: Int, pixels: [Float]) -> Data {
        var data = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y \(height) +X \(width)\n".utf8)
        for index in 0 ..< width * height {
            let r = pixels[index * 3]
            let g = pixels[index * 3 + 1]
            let b = pixels[index * 3 + 2]
            let peak = max(r, g, b)
            guard peak > 1e-32 else {
                data.append(contentsOf: [0, 0, 0, 0])
                continue
            }
            let exponent = Int(peak.exponent) + 1
            let scale = Float(sign: .plus, exponent: 8 - exponent, significand: 1)
            data.append(contentsOf: [UInt8(min(r * scale, 255)), UInt8(min(g * scale, 255)), UInt8(min(b * scale, 255)), UInt8(exponent + 128)])
        }
        return data
    }

    /// The pixel's colour at a direction (y up, the map's middle column looking down −z, as Blender lays it out).
    public func sample(_ direction: Vec3) -> Vec3 {
        let d = direction.normalized
        let u = 0.5 + atan2(d.x, -d.z) / (2 * .pi)
        let v = acos(max(-1, min(1, d.y))) / .pi
        let column = min(max(Int(u * Double(width)), 0), width - 1)
        let row = min(max(Int(v * Double(height)), 0), height - 1)
        let index = (row * width + column) * 3
        return Vec3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2]))
    }

    /// The direction a pixel looks along (its centre).
    public func direction(column: Int, row: Int) -> Vec3 {
        let u = (Double(column) + 0.5) / Double(width)
        let v = (Double(row) + 0.5) / Double(height)
        let azimuth = (u - 0.5) * 2 * .pi
        let polar = v * .pi
        return Vec3(sin(polar) * sin(azimuth), cos(polar), -sin(polar) * cos(azimuth))
    }
}
