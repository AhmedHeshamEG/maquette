import Foundation

/// Photoshop's PSD and large-document PSB files, read in pure Swift (L2, D-487): RGB and greyscale, 8 and 16 bits a
/// channel, every layer with its place, name (the Unicode one when there is one), opacity, visibility, mixing and the
/// groups it sits in; raw, RLE and zip-compressed pixels. Adjustment and fill layers, which hold no pixels of their own,
/// are counted rather than drawn. A file with no layers comes in as its one picture.
public enum PSDReader {
    public static let fileExtensions: Set<String> = ["psd", "psb"]

    public static func isPSD(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x38, 0x42, 0x50, 0x53])
    }

    public static func read(_ data: Data) throws(LayeredReadFailure) -> LayeredImage {
        var reader = BigEndianReader(data)
        guard isPSD(data) else { throw .notLayered }
        try reader.skip(4)
        let version = try reader.u16()
        guard version == 1 || version == 2 else { throw .unsupported("this Photoshop file version (\(version))") }
        try reader.skip(6)
        let channels = try reader.u16()
        let height = try reader.u32()
        let width = try reader.u32()
        let depth = try reader.u16()
        let mode = try reader.u16()
        guard depth == 8 || depth == 16 else { throw .unsupported("\(depth)-bit Photoshop files; save a copy in 8 or 16 bits") }
        guard mode == 3 || mode == 1 else { throw .unsupported("this colour mode; save a copy as RGB") }
        guard width > 0, height > 0, width <= 30000, height <= 30000 else { throw .damaged("the canvas size") }
        let header = Header(version: version, channels: channels, width: width, height: height, depth: depth, grey: mode == 1)
        try reader.skipBlock()
        try reader.skipBlock()
        let sectionLength = try header.large ? reader.u64() : reader.u32()
        let sectionEnd = reader.position + sectionLength
        var image = LayeredImage(width: width, height: height, layers: [])
        if sectionLength > 0 {
            image = try layers(&reader, header: header, sectionEnd: sectionEnd)
        }
        if image.layers.isEmpty, image.skipped.isEmpty {
            reader.position = sectionEnd
            let merged = try mergedPicture(&reader, header: header)
            image.layers = [LayeredImage.Layer(name: "Background", x: 0, y: 0, image: merged)]
        }
        return image
    }

    struct Header {
        var version: Int
        var channels: Int
        var width: Int
        var height: Int
        var depth: Int
        var grey: Bool

        var large: Bool { version == 2 }
    }

    // MARK: Layers

    private static func layers(_ reader: inout BigEndianReader, header: Header, sectionEnd: Int) throws(LayeredReadFailure) -> LayeredImage {
        let infoLength = try header.large ? reader.u64() : reader.u32()
        var image = LayeredImage(width: header.width, height: header.height, layers: [])
        if infoLength > 0 {
            var info = BigEndianReader(Data(try reader.slice(infoLength)))
            image = try layerInfo(&info, header: header)
            return image
        }
        // 16-bit documents keep their layers in a tagged block after the global mask ("Lr16").
        try reader.skipBlock()
        while reader.position + 12 <= sectionEnd {
            guard let signature = reader.peekASCII(4), signature == "8BIM" || signature == "8B64" else { break }
            try reader.skip(4)
            let key = try reader.ascii(4)
            let length = try header.large && PSDTags.longKeys.contains(key) ? reader.u64() : reader.u32()
            let start = reader.position
            if key == "Lr16" || key == "Lr32" || key == "Layr" {
                var info = BigEndianReader(Data(try reader.slice(length)))
                return try layerInfo(&info, header: header)
            }
            reader.position = start + length
            PSDTags.realign(&reader, end: sectionEnd)
        }
        return image
    }

    private static func layerInfo(_ reader: inout BigEndianReader, header: Header) throws(LayeredReadFailure) -> LayeredImage {
        let count = abs(try reader.i16())
        var records: [PSDRecord] = []
        for _ in 0 ..< count {
            try records.append(PSDRecord.read(&reader, large: header.large))
        }
        var layers: [LayeredImage.Layer] = []
        var skipped: [String: Int] = [:]
        var groups = PSDGroups()
        for record in records {
            let pixels = try record.pixels(&reader, header: header)
            switch record.section {
            case .end:
                groups.open()
                continue
            case .folder:
                groups.close(record, into: &layers)
                continue
            case .none:
                break
            }
            // Shape layers are fill layers that keep their drawn pixels too: whatever has pixels comes in.
            guard let pixels, record.width > 0, record.height > 0 else {
                skipped[record.adjustment ?? "empty layer", default: 0] += 1
                continue
            }
            groups.add(layers.count)
            layers.append(LayeredImage.Layer(name: record.name, x: record.left, y: record.top, image: pixels, opacity: Double(record.opacity) / 255,
                                             hidden: record.hidden, blend: record.blend))
        }
        return LayeredImage(width: header.width, height: header.height, layers: layers, skipped: skipped)
    }

    // MARK: The merged picture

    private static func mergedPicture(_ reader: inout BigEndianReader, header: Header) throws(LayeredReadFailure) -> RGBAImage {
        let compression = try reader.u16()
        // The merged picture is drawn opaque: its extra channels may be selections rather than transparency.
        let planes = min(header.channels, header.grey ? 1 : 3)
        let wanted = header.grey ? [0, 0, 0] : [0, 1, 2]
        var channels: [[UInt8]] = []
        switch compression {
        case 0:
            for _ in 0 ..< planes {
                try channels.append(PSDPixels.raw(&reader, width: header.width, height: header.height, depth: header.depth))
            }
        case 1:
            var counts: [Int] = []
            for _ in 0 ..< header.channels * header.height {
                try counts.append(header.large ? reader.u32() : reader.u16())
            }
            for plane in 0 ..< planes {
                let rows = Array(counts[plane * header.height ..< (plane + 1) * header.height])
                try channels.append(PSDPixels.packBits(&reader, rows: rows, width: header.width, depth: header.depth))
            }
        default:
            throw .unsupported("this Photoshop file's compression")
        }
        guard channels.count == planes, planes > 0 else { throw .damaged("the picture") }
        return PSDPixels.picture(width: header.width, height: header.height, channels: wanted.map { channels[min($0, planes - 1)] }, alpha: nil)
    }
}

/// Groups as Photoshop lists them, bottom first: an end marker, the group's layers, then the group's own record with its
/// name, visibility and opacity. Layers learn their groups when the group closes.
struct PSDGroups {
    private var frames: [[Int]] = []

    mutating func open() {
        frames.append([])
    }

    mutating func add(_ index: Int) {
        if !frames.isEmpty { frames[frames.count - 1].append(index) }
    }

    mutating func close(_ record: PSDRecord, into layers: inout [LayeredImage.Layer]) {
        guard let members = frames.popLast() else { return }
        for index in members {
            layers[index].groups.insert(record.name, at: 0)
            if record.hidden { layers[index].hidden = true }
            layers[index].opacity *= Double(record.opacity) / 255
        }
        if !frames.isEmpty { frames[frames.count - 1] += members }
    }
}
