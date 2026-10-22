import Foundation

/// Messages on a link travel as frames: four bytes of length (big-endian), then that many bytes. A frame can carry a
/// whole file (a scan, a model for AR), which newline-separated JSON couldn't.
public enum HmmFrames {
    /// The largest frame a reader accepts (a model or a scan, with room to spare).
    public static let maximumLength = 256 * 1024 * 1024

    public static func frame(_ payload: Data) -> Data {
        var data = Data(capacity: payload.count + 4)
        let length = UInt32(payload.count)
        data.append(UInt8(length >> 24 & 0xFF))
        data.append(UInt8(length >> 16 & 0xFF))
        data.append(UInt8(length >> 8 & 0xFF))
        data.append(UInt8(length & 0xFF))
        data.append(payload)
        return data
    }

    public static func frame(_ message: some Encodable) throws -> Data {
        try frame(JSONEncoder().encode(message))
    }
}

/// Reads frames out of bytes as they arrive, in whatever pieces the network hands them over.
public struct HmmFrameReader: Sendable {
    public enum Failure: Error, Equatable {
        /// A frame said it was longer than `HmmFrames.maximumLength`: the stream is not ours or is broken.
        case tooLong(Int)
    }

    private var pending = Data()

    public init() {}

    /// Bytes waiting for the rest of their frame.
    public var waiting: Int { pending.count }

    /// Adds `bytes` and returns every frame now complete, in order.
    public mutating func read(_ bytes: Data) throws -> [Data] {
        pending.append(bytes)
        var frames: [Data] = []
        while pending.count >= 4 {
            let start = pending.startIndex
            let length = Int(pending[start]) << 24 | Int(pending[start + 1]) << 16 | Int(pending[start + 2]) << 8 | Int(pending[start + 3])
            guard length <= HmmFrames.maximumLength else {
                pending = Data()
                throw Failure.tooLong(length)
            }
            guard pending.count >= 4 + length else { break }
            frames.append(Data(pending[(start + 4) ..< (start + 4 + length)]))
            pending = Data(pending[(start + 4 + length)...])
        }
        return frames
    }
}
