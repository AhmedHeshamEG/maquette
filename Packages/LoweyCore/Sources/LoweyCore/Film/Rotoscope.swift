import Foundation

/// Rotoscoping (F1): a video stands behind the stage, its frame always the one under the playhead, so a character can
/// be posed or drawn over a real movement frame by frame. It's a reference: the stage shows it, exports never do.
public struct Rotoscope: Codable, Hashable, Sendable {
    /// The video's asset key in the project (`assets/…`).
    public var video: String
    /// How much of the video shows, 0…1.
    public var opacity: Double
    /// Where the video starts on the timeline (seconds; negative starts it partway in).
    public var start: Double
    /// Shown on the stage (it stays in the project when hidden).
    public var shown: Bool
    /// Over the scene, faintly, instead of behind it: to trace a shape the scene would hide.
    public var inFront: Bool

    public init(video: String, opacity: Double = 0.6, start: Double = 0, shown: Bool = true, inFront: Bool = false) {
        self.video = video
        self.opacity = opacity
        self.start = start
        self.shown = shown
        self.inFront = inFront
    }

    /// The video's own time for a timeline moment, nil before it starts.
    public func videoTime(at time: Double, length: Double? = nil) -> Double? {
        let local = time - start
        guard local >= -1e-9 else { return nil }
        if let length, local > length { return nil }
        return max(local, 0)
    }

    /// The video's frame for a timeline moment at its frame rate, snapped so scrubbing shows whole frames.
    public func frameTime(at time: Double, fps: Double, length: Double? = nil) -> Double? {
        guard let local = videoTime(at: time, length: length), fps > 0 else { return nil }
        return (local * fps + 1e-6).rounded(.down) / fps
    }

    var clamped: Rotoscope {
        var copy = self
        copy.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 0.6
        copy.start = start.isFinite ? start : 0
        return copy
    }
}
