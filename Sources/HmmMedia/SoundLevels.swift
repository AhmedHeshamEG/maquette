import Foundation

/// What a sound does over time, measured once so anything can move to it: how loud it is and how much bass it has,
/// sixty times a second (0…1, against the sound's own quiet and loud), and where its beats fall. Times are seconds
/// into the file. Small enough to keep in a project: three minutes are about 20 KB.
public struct SoundLevels: Hashable, Sendable {
    /// Values a second.
    public static let rate = 60.0

    /// Loudness, 0…255 (the envelope: quick to rise, slower to fall).
    public var loudness: [UInt8]
    /// The bass under about 150 Hz, the same way.
    public var bass: [UInt8]
    /// Beats, in seconds, rising.
    public var beats: [Double]
    /// Beats a minute when the sound keeps a steady pulse (nil for speech and free time).
    public var tempo: Double?

    public init(loudness: [UInt8], bass: [UInt8], beats: [Double], tempo: Double?) {
        self.loudness = loudness
        self.bass = bass
        self.beats = beats
        self.tempo = tempo
    }

    public static let silent = SoundLevels(loudness: [], bass: [], beats: [], tempo: nil)

    public var duration: Double { Double(loudness.count) / Self.rate }

    /// Loudness at `time` seconds into the file, 0…1 (between measurements, a straight line).
    public func loudness(at time: Double) -> Double { Self.sample(loudness, at: time) }

    /// The bass at `time`, 0…1.
    public func bass(at time: Double) -> Double { Self.sample(bass, at: time) }

    /// A hit on each beat: 1 on the beat, falling away over `release` seconds, and rising over the last 30 ms before it so
    /// the jump isn't a hard step.
    public func pulse(at time: Double, release: Double = 0.25) -> Double {
        guard !beats.isEmpty else { return 0 }
        let next = beats.firstIndex { $0 > time } ?? beats.count
        var value = 0.0
        if next > 0 {
            let since = time - beats[next - 1]
            value = exp(-since / max(release, 0.01))
        }
        if next < beats.count {
            let until = beats[next] - time
            if until < 0.03 { value = max(value, 1 - until / 0.03) }
        }
        return value
    }

    static func sample(_ values: [UInt8], at time: Double) -> Double {
        guard !values.isEmpty, time >= 0 else { return 0 }
        let position = time * rate
        let lower = Int(position.rounded(.down))
        guard lower < values.count - 1 else { return lower < values.count ? Double(values[lower]) / 255 : 0 }
        let blend = position - Double(lower)
        return (Double(values[lower]) * (1 - blend) + Double(values[lower + 1]) * blend) / 255
    }
}

extension SoundLevels: Codable {
    private enum CodingKeys: String, CodingKey { case loudness, bass, beats, tempo }

    /// The levels as base64 (one byte a value), so a project stays readable and small.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loudness = try [UInt8](Data(base64Encoded: c.decode(String.self, forKey: .loudness)) ?? Data())
        bass = try [UInt8](Data(base64Encoded: c.decode(String.self, forKey: .bass)) ?? Data())
        beats = try c.decodeIfPresent([Double].self, forKey: .beats) ?? []
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Data(loudness).base64EncodedString(), forKey: .loudness)
        try c.encode(Data(bass).base64EncodedString(), forKey: .bass)
        try c.encode(beats.map { ($0 * 1000).rounded() / 1000 }, forKey: .beats)
        try c.encodeIfPresent(tempo.map { ($0 * 10).rounded() / 10 }, forKey: .tempo)
    }
}
