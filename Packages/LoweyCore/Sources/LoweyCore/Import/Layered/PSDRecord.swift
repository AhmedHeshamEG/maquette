import Foundation

/// One layer record of a PSD: where it is, its channels, how it mixes, its name and what kind of layer it is.
struct PSDRecord {
    enum Section {
        case none
        /// The marker below a group's layers.
        case end
        /// The group's own record, above its layers.
        case folder
    }

    var top = 0
    var left = 0
    var bottom = 0
    var right = 0
    var channels: [(id: Int, length: Int)] = []
    var blend = LayerBlend.normal
    var opacity = 255
    var hidden = false
    var name = ""
    var section = Section.none
    /// An adjustment or fill layer: what it was, for the skipped count.
    var adjustment: String?

    var width: Int { max(right - left, 0) }
    var height: Int { max(bottom - top, 0) }

    static func read(_ reader: inout BigEndianReader, large: Bool) throws(LayeredReadFailure) -> PSDRecord {
        var record = PSDRecord()
        record.top = try reader.i32()
        record.left = try reader.i32()
        record.bottom = try reader.i32()
        record.right = try reader.i32()
        guard record.width <= 30000, record.height <= 30000 else { throw .damaged("a layer's size") }
        let count = try reader.u16()
        for _ in 0 ..< count {
            try record.channels.append((reader.i16(), large ? reader.u64() : reader.u32()))
        }
        guard try reader.ascii(4) == "8BIM" else { throw .damaged("a layer's mixing") }
        record.blend = try PSDTags.blend(reader.ascii(4))
        record.opacity = try reader.u8()
        try reader.skip(1)
        record.hidden = try reader.u8() & 0x02 != 0
        try reader.skip(1)
        let extraLength = try reader.u32()
        let end = reader.position + extraLength
        try reader.skipBlock()
        try reader.skipBlock()
        let nameLength = try reader.u8()
        record.name = try PSDTags.legacyName(reader.slice(nameLength))
        try reader.skip((nameLength + 4) / 4 * 4 - 1 - nameLength)
        try record.readTags(&reader, end: end, large: large)
        reader.position = end
        return record
    }

    private mutating func readTags(_ reader: inout BigEndianReader, end: Int, large: Bool) throws(LayeredReadFailure) {
        while reader.position + 12 <= end {
            guard let signature = reader.peekASCII(4), signature == "8BIM" || signature == "8B64" else { return }
            try reader.skip(4)
            let key = try reader.ascii(4)
            let length = try large && PSDTags.longKeys.contains(key) ? reader.u64() : reader.u32()
            let start = reader.position
            guard start + length <= end else { return }
            switch key {
            case "luni":
                let count = try reader.u32()
                var units: [UInt16] = []
                for _ in 0 ..< min(count, (length - 4) / 2) {
                    try units.append(UInt16(reader.u16()))
                }
                let unicode = String(decoding: units, as: UTF16.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                if !unicode.isEmpty { name = unicode }
            case "lsct", "lsdk":
                let type = try reader.u32()
                section = type == 3 ? .end : type == 1 || type == 2 ? .folder : .none
            default:
                if PSDTags.fills.contains(key) {
                    adjustment = "fill layer"
                } else if PSDTags.adjustments.contains(key) {
                    adjustment = "adjustment layer"
                }
            }
            reader.position = start + length
            PSDTags.realign(&reader, end: end)
        }
    }

    /// The layer's picture (nil when it has none to show), reading past every channel either way.
    func pixels(_ reader: inout BigEndianReader, header: PSDReader.Header) throws(LayeredReadFailure) -> RGBAImage? {
        var planes: [Int: [UInt8]] = [:]
        for channel in channels {
            let start = reader.position
            guard start + channel.length <= reader.bytes.count else { throw .damaged("a layer's pixels") }
            let wanted = [0, 1, 2, -1].contains(channel.id) && width > 0 && height > 0 && channel.length > 2
            if wanted {
                planes[channel.id] = try PSDPixels.channel(&reader, length: channel.length, width: width, height: height, header: header)
            }
            reader.position = start + channel.length
        }
        guard width > 0, height > 0, let red = planes[0] else { return nil }
        let colours = header.grey ? [red, red, red] : [red, planes[1] ?? red, planes[2] ?? red]
        return PSDPixels.picture(width: width, height: height, channels: colours, alpha: planes[-1])
    }
}

/// Photoshop's tagged-block words.
enum PSDTags {
    /// Blocks whose length is eight bytes in a PSB.
    static let longKeys: Set<String> = ["LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD"]
    static let fills: Set<String> = ["SoCo", "GdFl", "PtFl"]
    static let adjustments: Set<String> = ["levl", "curv", "brit", "hue ", "hue2", "blnc", "vibA", "expA", "post", "thrs", "grdm", "selc",
                                           "mixr", "clrL", "phfl", "blwh", "nvrt", "CgEd"]

    static func blend(_ key: String) -> LayerBlend {
        switch key {
        case "norm", "pass": .normal
        case "mul ": .multiply
        case "scrn": .screen
        case "over": .overlay
        case "lddg": .add
        case "dark": .darken
        case "lite": .lighten
        case "sLit": .softLight
        case "hLit": .hardLight
        case "div ": .colorDodge
        case "idiv": .colorBurn
        case "diff": .difference
        default: .other
        }
    }

    /// The old Pascal name (Mac Roman in older files; Latin-1 reads the same for plain letters).
    static func legacyName(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    /// Writers pad a block to two or four bytes; finds the next block's signature within three bytes.
    static func realign(_ reader: inout BigEndianReader, end: Int) {
        for offset in 0 ... 3 where reader.position + offset + 4 <= end {
            var probe = reader
            probe.position += offset
            if let signature = probe.peekASCII(4), signature == "8BIM" || signature == "8B64" {
                reader.position = probe.position
                return
            }
        }
    }
}

/// A channel's samples, decompressed and brought to eight bits.
enum PSDPixels {
    static func channel(_ reader: inout BigEndianReader, length: Int, width: Int, height: Int,
                        header: PSDReader.Header) throws(LayeredReadFailure) -> [UInt8] {
        let compression = try reader.u16()
        switch compression {
        case 0:
            return try raw(&reader, width: width, height: height, depth: header.depth)
        case 1:
            var rows: [Int] = []
            for _ in 0 ..< height {
                try rows.append(header.large ? reader.u32() : reader.u16())
            }
            return try packBits(&reader, rows: rows, width: width, depth: header.depth)
        case 2, 3:
            let packed = try reader.slice(length - 2)
            guard packed.count > 2 else { throw .damaged("a zipped channel") }
            let inflated: Data
            do {
                inflated = try Inflate.decompress(Data(packed.dropFirst(2)), expectedSize: width * height * header.depth / 8)
            } catch {
                throw .damaged("a zipped channel")
            }
            var bytes = [UInt8](inflated)
            guard bytes.count >= width * height * header.depth / 8 else { throw .damaged("a zipped channel") }
            if compression == 3 { undoPrediction(&bytes, width: width, height: height, depth: header.depth) }
            return eight(bytes, depth: header.depth, count: width * height)
        default:
            throw .unsupported("this Photoshop compression")
        }
    }

    static func raw(_ reader: inout BigEndianReader, width: Int, height: Int, depth: Int) throws(LayeredReadFailure) -> [UInt8] {
        try eight(Array(reader.slice(width * height * depth / 8)), depth: depth, count: width * height)
    }

    /// PackBits rows (Apple's run-length code): a count byte, then literal bytes or one byte repeated.
    static func packBits(_ reader: inout BigEndianReader, rows: [Int], width: Int, depth: Int) throws(LayeredReadFailure) -> [UInt8] {
        let rowBytes = width * depth / 8
        var output = [UInt8]()
        output.reserveCapacity(rowBytes * rows.count)
        for count in rows {
            let row = try reader.slice(count)
            var index = row.startIndex
            var written = 0
            while index < row.endIndex, written < rowBytes {
                let header = Int(Int8(bitPattern: row[index]))
                index += 1
                if header >= 0 {
                    let run = min(header + 1, row.endIndex - index, rowBytes - written)
                    output.append(contentsOf: row[index ..< index + run])
                    index += header + 1
                    written += run
                } else if header > -128, index < row.endIndex {
                    let run = min(1 - header, rowBytes - written)
                    output.append(contentsOf: repeatElement(row[index], count: run))
                    index += 1
                    written += run
                }
            }
            if written < rowBytes { output.append(contentsOf: repeatElement(0, count: rowBytes - written)) }
        }
        return eight(output, depth: depth, count: width * rows.count)
    }

    static func undoPrediction(_ bytes: inout [UInt8], width: Int, height: Int, depth: Int) {
        for row in 0 ..< height {
            if depth == 16 {
                var previous: UInt16 = 0
                for column in 0 ..< width {
                    let index = (row * width + column) * 2
                    let value = (UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])) &+ previous
                    bytes[index] = UInt8(value >> 8)
                    bytes[index + 1] = UInt8(value & 0xFF)
                    previous = value
                }
            } else {
                for column in 1 ..< max(width, 1) {
                    bytes[row * width + column] &+= bytes[row * width + column - 1]
                }
            }
        }
    }

    /// Sixteen-bit samples keep their top byte.
    static func eight(_ bytes: [UInt8], depth: Int, count: Int) -> [UInt8] {
        guard depth == 16 else { return Array(bytes.prefix(count)) }
        return (0 ..< min(count, bytes.count / 2)).map { bytes[$0 * 2] }
    }

    static func picture(width: Int, height: Int, channels: [[UInt8]], alpha: [UInt8]?) -> RGBAImage {
        let count = width * height
        var pixels = [UInt8](repeating: 0, count: count * 4)
        for index in 0 ..< count {
            for channel in 0 ..< 3 where index < channels[channel].count {
                pixels[index * 4 + channel] = channels[channel][index]
            }
            pixels[index * 4 + 3] = alpha.map { index < $0.count ? $0[index] : 255 } ?? 255
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }
}
