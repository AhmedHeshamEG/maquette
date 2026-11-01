import Foundation

/// Marks an MP4 or MOV as 360° video: the Spherical Video (V1) metadata YouTube, Facebook, Quest and every 360 player
/// read, an XML `uuid` box in the video track. AVFoundation writes no such box, so it is added to the finished file:
/// the track and movie boxes grow by its size, and when the movie box comes before the media the chunk offsets move
/// by it too. Pure Swift, so it's tested anywhere.
public enum SphericalVideo {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notMP4
        case noVideoTrack
        case alreadySpherical

        public var description: String {
            switch self {
            case .notMP4: "That isn't an MP4 or MOV file."
            case .noVideoTrack: "The file has no video track."
            case .alreadySpherical: "The file is already marked as 360° video."
            }
        }
    }

    /// The V1 box's id.
    static let uuid: [UInt8] = [0xFF, 0xCC, 0x82, 0x63, 0xF8, 0x55, 0x4A, 0x93, 0x88, 0x14, 0x58, 0x7A, 0x02, 0x52, 0x1F, 0xDD]

    static func xml(software: String) -> String {
        """
        <?xml version="1.0"?><rdf:SphericalVideo xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" \
        xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/"><GSpherical:Spherical>true</GSpherical:Spherical>\
        <GSpherical:Stitched>true</GSpherical:Stitched><GSpherical:StitchingSoftware>\(software)</GSpherical:StitchingSoftware>\
        <GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType></rdf:SphericalVideo>
        """
    }

    /// The file with the 360° box in its first video track.
    public static func inject(_ data: Data, software: String = "studio h.") throws(Failure) -> Data {
        var bytes = [UInt8](data)
        let top = boxes(bytes, 0, bytes.count)
        guard let moov = top.first(where: { $0.type == "moov" }) else { throw .notMP4 }
        let tracks = boxes(bytes, moov.body, moov.end).filter { $0.type == "trak" }
        guard let video = tracks.first(where: { isVideo(bytes, $0) }) else { throw .noVideoTrack }
        if boxes(bytes, video.body, video.end).contains(where: { $0.type == "uuid" && Array(bytes[$0.body ..< $0.body + 16]) == uuid }) {
            throw .alreadySpherical
        }
        let payload = Array(xml(software: software).utf8)
        let box = be32(UInt32(8 + 16 + payload.count)) + Array("uuid".utf8) + uuid + payload
        let delta = box.count
        // Media after the movie box moves along: every chunk offset that points past the insertion grows.
        if top.contains(where: { $0.type == "mdat" && $0.start > moov.start }) {
            for track in tracks {
                shiftChunkOffsets(&bytes, in: track, by: delta)
            }
        }
        bytes.insert(contentsOf: box, at: video.end)
        grow(&bytes, video, by: delta)
        grow(&bytes, moov, by: delta)
        return Data(bytes)
    }

    /// Whether a file already carries the 360° box.
    public static func isSpherical(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard let moov = boxes(bytes, 0, bytes.count).first(where: { $0.type == "moov" }) else { return false }
        return boxes(bytes, moov.body, moov.end).filter { $0.type == "trak" }.contains { track in
            boxes(bytes, track.body, track.end).contains { box in
                box.type == "uuid" && box.end - box.body >= 16 && Array(bytes[box.body ..< box.body + 16]) == uuid
            }
        }
    }

    public static func injectFile(_ url: URL, software: String = "studio h.") throws {
        let marked = try inject(Data(contentsOf: url), software: software)
        try marked.write(to: url, options: .atomic)
    }

    // MARK: Boxes

    struct Box {
        var type: String
        var start: Int
        /// Where the contents begin (after the size, the type and a 64-bit size when there is one).
        var body: Int
        var end: Int
        var isLarge: Bool
    }

    static func boxes(_ bytes: [UInt8], _ from: Int, _ to: Int) -> [Box] {
        var result: [Box] = []
        var cursor = from
        while cursor + 8 <= to {
            var size = Int(u32(bytes, cursor))
            let type = String(decoding: bytes[cursor + 4 ..< cursor + 8], as: UTF8.self)
            var body = cursor + 8
            var large = false
            if size == 1, cursor + 16 <= to {
                size = Int(u64(bytes, cursor + 8))
                body += 8
                large = true
            } else if size == 0 {
                size = to - cursor
            }
            guard size >= body - cursor, cursor + size <= to else { break }
            result.append(Box(type: type, start: cursor, body: body, end: cursor + size, isLarge: large))
            cursor += size
        }
        return result
    }

    static func isVideo(_ bytes: [UInt8], _ track: Box) -> Bool {
        guard let mdia = boxes(bytes, track.body, track.end).first(where: { $0.type == "mdia" }),
              let hdlr = boxes(bytes, mdia.body, mdia.end).first(where: { $0.type == "hdlr" }), hdlr.body + 12 <= hdlr.end else { return false }
        // Full box: version and flags (4), pre-defined (4), then the handler type.
        return String(decoding: bytes[hdlr.body + 8 ..< hdlr.body + 12], as: UTF8.self) == "vide"
    }

    static func shiftChunkOffsets(_ bytes: inout [UInt8], in track: Box, by delta: Int) {
        guard let mdia = boxes(bytes, track.body, track.end).first(where: { $0.type == "mdia" }),
              let minf = boxes(bytes, mdia.body, mdia.end).first(where: { $0.type == "minf" }),
              let stbl = boxes(bytes, minf.body, minf.end).first(where: { $0.type == "stbl" }) else { return }
        for table in boxes(bytes, stbl.body, stbl.end) where table.type == "stco" || table.type == "co64" {
            let count = Int(u32(bytes, table.body + 4))
            let wide = table.type == "co64"
            for index in 0 ..< count {
                let at = table.body + 8 + index * (wide ? 8 : 4)
                guard at + (wide ? 8 : 4) <= table.end else { break }
                if wide {
                    write(&bytes, be64(u64(bytes, at) + UInt64(delta)), at: at)
                } else {
                    write(&bytes, be32(u32(bytes, at) &+ UInt32(delta)), at: at)
                }
            }
        }
    }

    static func grow(_ bytes: inout [UInt8], _ box: Box, by delta: Int) {
        if box.isLarge {
            write(&bytes, be64(UInt64(box.end - box.start + delta)), at: box.start + 8)
        } else {
            write(&bytes, be32(UInt32(box.end - box.start + delta)), at: box.start)
        }
    }

    static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        bytes[at ..< at + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func u64(_ bytes: [UInt8], _ at: Int) -> UInt64 {
        bytes[at ..< at + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }

    static func be32(_ value: UInt32) -> [UInt8] { (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
    static func be64(_ value: UInt64) -> [UInt8] { (0 ..< 8).map { UInt8(truncatingIfNeeded: value >> (56 - 8 * $0)) } }

    static func write(_ bytes: inout [UInt8], _ value: [UInt8], at offset: Int) {
        for (index, byte) in value.enumerated() {
            bytes[offset + index] = byte
        }
    }
}
