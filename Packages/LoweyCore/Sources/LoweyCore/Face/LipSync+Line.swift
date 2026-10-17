import Foundation

/// A line typed rather than recorded (K1, "Say a line"): its words are laid out at an easy speaking pace from a moment on
/// the timeline, so a character lip-syncs to what it will say before there's a voice (a game clip, a storyboard, a
/// recording planned for later).
public extension LipSync {
    /// About 150 words a minute, a short word quicker than a long one, a breath at each full stop or comma.
    static func timedLine(_ text: String, from start: Double) -> [TimelineWord] {
        var words: [TimelineWord] = []
        var time = start
        for (index, raw) in text.split(whereSeparator: \.isWhitespace).enumerated() {
            let letters = raw.filter(\.isLetter).count + raw.filter(\.isNumber).count * 3
            guard letters > 0 else { continue }
            let length = min(max(0.16 + Double(letters) * 0.055, 0.22), 0.9)
            words.append(TimelineWord(clip: "line", index: index, text: String(raw), start: time, end: time + length))
            time += length
            if let last = raw.last, ".!?".contains(last) {
                time += 0.4
            } else if let last = raw.last, ",;:".contains(last) {
                time += 0.22
            } else {
                time += 0.04
            }
        }
        return words
    }

    /// The keys that make `character` say a typed line from `start` (nil when there are no words in it).
    static func line(_ text: String, character: ObjectID, from start: Double, language: String, timeline: Timeline,
                     ids: inout IDFactory) -> EditCommand? {
        let words = timedLine(text, from: start)
        guard let first = words.first, let last = words.last else { return nil }
        let shapes = shapes(for: words, language: language)
        guard let keys = keys(shapes, character: character, range: TimeRange(start: first.start, end: last.end + 0.2), timeline: timeline,
                              ids: &ids) else { return nil }
        // The timeline grows to hold the line.
        var commands = [keys]
        if last.end + 0.4 > timeline.duration {
            var longer = timeline
            longer.duration = (last.end + 0.5).rounded(.up)
            if case let .batch(_, inner) = keys {
                commands = [.setTimeline(Self.applying(inner, to: longer))]
            }
        }
        return .batch("Say “\(text.count > 24 ? String(text.prefix(24)) + "…" : text)”", commands)
    }

    /// A timeline with track edits applied (to lengthen it and add the line's keys in one step).
    private static func applying(_ commands: [EditCommand], to timeline: Timeline) -> Timeline {
        var result = timeline
        for case let .setTracks(edits) in commands {
            for edit in edits {
                result.tracks.removeAll { $0.id == edit.id }
                if let track = edit.track { result.tracks.append(track) }
            }
        }
        return result
    }
}
