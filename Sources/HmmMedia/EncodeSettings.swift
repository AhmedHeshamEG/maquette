import Foundation

/// The codecs the hmm. apps write.
public enum VideoCodecKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case h264
    case hevc
    /// HEVC with an alpha channel (.mov): transparent exports.
    case hevcAlpha
    /// ProRes 4444 (.mov): editing masters with alpha.
    case prores4444
    /// 10-bit HEVC in HDR: HLG, BT.2020 (.mov). Its frames are half floats already in HLG (`isHDR`).
    case hevcHDR

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .hevcAlpha: "HEVC with transparency"
        case .prores4444: "ProRes 4444"
        case .hevcHDR: "HEVC HDR (HLG)"
        }
    }

    public var hasAlpha: Bool { self == .hevcAlpha || self == .prores4444 }

    /// High dynamic range: the encoder's buffers are RGBA half floats holding HLG-encoded BT.2020 colour, so a renderer
    /// writes brighter-than-white highlights and wide colour straight into them.
    public var isHDR: Bool { self == .hevcHDR }

    /// .mp4 for the delivery codecs, .mov when alpha, ProRes or HDR's colour tags need it.
    public var fileExtension: String { hasAlpha || isHDR ? "mov" : "mp4" }

    /// Average bits per pixel per frame for a good-looking delivery file.
    var bitsPerPixel: Double {
        switch self {
        case .h264: 0.12
        case .hevc, .hevcAlpha: 0.08
        case .hevcHDR: 0.11
        case .prores4444: 1.2
        }
    }
}

/// Everything an encode session needs to know.
public struct EncodeSettings: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var codec: VideoCodecKind
    /// "Quality" slider 0…1 (0.5 = the default bitrate, 1 = twice it).
    public var quality: Double
    /// Stereo interleaved audio sample rate (when there is audio).
    public var audioSampleRate: Int

    public init(width: Int, height: Int, fps: Int, codec: VideoCodecKind, quality: Double = 0.5, audioSampleRate: Int = 48000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.quality = quality
        self.audioSampleRate = audioSampleRate
    }

    /// Target average bitrate in bits per second.
    public var bitrate: Int {
        let factor = 0.5 + min(max(quality, 0), 1)
        return Int(Double(width * height * max(fps, 1)) * codec.bitsPerPixel * factor)
    }

    /// A keyframe every two seconds.
    public var keyframeInterval: Int { max(fps, 1) * 2 }

    /// Encoders need even dimensions.
    public var isValid: Bool { width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0 && fps > 0 }
}
