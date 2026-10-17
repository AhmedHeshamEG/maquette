import Foundation

// The standard Rhubarb / Preston Blair letters.
// swiftlint:disable identifier_name

/// Mouth shapes (Rhubarb Lip Sync / Preston Blair set). `X` is rest.
public enum Viseme: String, Codable, Sendable, CaseIterable {
    /// Closed: M, B, P.
    case A
    /// Slightly open, teeth together: most consonants, EE.
    case B
    /// Open: EH, AE, AH.
    case C
    /// Wide open: AA.
    case D
    /// Rounded: AO, ER.
    case E
    /// Puckered: OO, OW, W.
    case F
    /// Lip bite: F, V.
    case G
    /// Tongue up: L.
    case H
    /// Rest (mouth closed, relaxed).
    case X

    /// How open the jaw is for this shape (drives 3D jaws and scales mouths without shape sets).
    public var jaw: Double {
        switch self {
        case .A, .X: 0
        case .B: 0.15
        case .C: 0.5
        case .D: 0.9
        case .E: 0.45
        case .F: 0.25
        case .G: 0.1
        case .H: 0.4
        }
    }

    /// −1 (narrow, puckered) … 1 (wide).
    public var width: Double {
        switch self {
        case .A, .X: 0
        case .B: 0.45
        case .C: 0.3
        case .D: 0.2
        case .E: -0.4
        case .F: -0.8
        case .G: 0.1
        case .H: 0.15
        }
    }
}

// swiftlint:enable identifier_name

/// Word → mouth shapes: the CMU Pronouncing Dictionary for English (visemes.txt, built by scripts/make_visemes.py),
/// letter-to-sound rules for unknown English words and for Italian, and a letter map for Arabic.
public final class Phonemizer: @unchecked Sendable {
    public static let shared = Phonemizer()

    private let lock = NSLock()
    private var dictionary: [Substring: Substring]?
    private var text = ""

    public init() {}

    /// Number of dictionary words (0 when the resource is missing — rules still work).
    public var dictionarySize: Int { loadedDictionary().count }

    private func loadedDictionary() -> [Substring: Substring] {
        lock.lock()
        defer { lock.unlock() }
        if let dictionary { return dictionary }
        var map: [Substring: Substring] = [:]
        if let url = Bundle.module.url(forResource: "visemes", withExtension: "txt"), let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
            map.reserveCapacity(130_000)
            for line in text.split(separator: "\n") {
                guard let space = line.firstIndex(of: " ") else { continue }
                map[line[..<space]] = line[line.index(after: space)...]
            }
        }
        dictionary = map
        return map
    }

    /// Mouth shapes of one word (the 14 of `MouthShape`), with a duration weight each (vowels get more time).
    public func shapes(for word: String, language: String) -> [(MouthShape, Double)] {
        let clean = word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        guard !clean.isEmpty else { return [] }
        if language.hasPrefix("ar") || clean.unicodeScalars.contains(where: { (0x0600 ... 0x06FF).contains($0.value) }) {
            return Self.arabic(clean)
        }
        if language.hasPrefix("it") { return Self.italian(clean) }
        if let entry = loadedDictionary()[Substring(clean)] { return Self.decode(entry) }
        if clean.allSatisfy(\.isNumber) { return Self.englishRules(Self.spelledNumber(clean)) }
        return Self.englishRules(clean)
    }

    /// The same as the nine Rhubarb shapes (swap sets drawn before 0.20, Blobs, the jaw and width keys).
    public func visemes(for word: String, language: String) -> [(Viseme, Double)] {
        shapes(for: word, language: language).map { ($0.0.viseme, $0.1) }
    }

    static func decode(_ entry: Substring) -> [(MouthShape, Double)] {
        entry.compactMap { character in
            guard let shape = MouthShape(letter: character) else { return nil }
            return (shape, character.isLowercase ? 1.4 : (shape == .m ? 0.7 : 0.8))
        }
    }

    /// Rough English letter-to-sound for words the dictionary doesn't know.
    static func englishRules(_ word: String) -> [(MouthShape, Double)] {
        let letters = Array(word.lowercased())
        var result: [(MouthShape, Double)] = []
        var index = 0
        func vowel(_ shape: MouthShape) { result.append((shape, 1.4)) }
        func consonant(_ shape: MouthShape) { result.append((shape, shape == .m ? 0.7 : 0.8)) }
        while index < letters.count {
            let next = index + 1 < letters.count ? letters[index + 1] : " "
            if let pair = Self.pairs["\(letters[index])\(next)"] {
                pair.vowel ? vowel(pair.shape) : consonant(pair.shape)
                index += 2
                continue
            }
            let c = letters[index]
            switch c {
            case "a": vowel(.ah)
            case "e": if index < letters.count - 1 || letters.count <= 2 { vowel(.ee) } // silent final e
            case "i", "y": vowel(.ee)
            case "o": vowel(.oh)
            case "u": vowel(.uh)
            default: if let shape = Self.consonants[c] { consonant(shape) } else if c.isLetter { consonant(.d) }
            }
            index += 1
        }
        return result
    }

    /// Two letters that make one sound.
    static let pairs: [String: (shape: MouthShape, vowel: Bool)] = [
        "th": (.d, false), "sh": (.s, false), "ch": (.s, false), "gh": (.d, false), "ph": (.f, false),
        "oo": (.wOo, true), "ou": (.wOo, true), "ow": (.oh, true), "ee": (.ee, true), "ea": (.ee, true), "ie": (.ee, true),
        "ai": (.ee, true), "ay": (.ee, true)
    ]

    static let consonants: [Character: MouthShape] = [
        "m": .m, "b": .m, "p": .m, "f": .f, "v": .f, "l": .l, "w": .wOo, "r": .r, "s": .s, "z": .s, "c": .s, "j": .s, "x": .s, "h": .uh
    ]

    /// Italian is (nearly) spelled as spoken.
    static func italian(_ word: String) -> [(MouthShape, Double)] {
        var result: [(MouthShape, Double)] = []
        for c in word.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            switch c {
            case "a": result.append((.ah, 1.4))
            case "e": result.append((.ee, 1.4))
            case "i": result.append((.ee, 1.3))
            case "o": result.append((.oh, 1.4))
            case "u": result.append((.wOo, 1.4))
            case "m", "b", "p": result.append((.m, 0.7))
            case "f", "v": result.append((.f, 0.8))
            case "l": result.append((.l, 0.8))
            case "r": result.append((.r, 0.8))
            case "s", "z", "c": result.append((.s, 0.8))
            case "h": continue
            default: if c.isLetter { result.append((.d, 0.8)) }
            }
        }
        return result
    }

    /// Arabic letters → mouth shapes. Short vowels are rarely written, so an open vowel is assumed after a
    /// consonant that isn't followed by a long vowel (it keeps the mouth moving like speech).
    static func arabic(_ word: String) -> [(MouthShape, Double)] {
        let longVowels: [Character: MouthShape] = ["ا": .ah, "آ": .ah, "ى": .ah, "و": .wOo, "ي": .ee]
        let marks: [Character: MouthShape] = ["َ": .uh, "ُ": .wOo, "ِ": .ee]
        let letters = Array(word)
        var result: [(MouthShape, Double)] = []
        for (index, c) in letters.enumerated() {
            if let mark = marks[c] {
                result.append((mark, 1.2))
                continue
            }
            if c.unicodeScalars.allSatisfy({ (0x064B ... 0x065F).contains($0.value) }) { continue } // other diacritics
            if let vowel = longVowels[c], index > 0 {
                result.append((vowel, 1.5))
                continue
            }
            result.append((Self.arabicConsonants[c] ?? .d, 0.8))
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            if let next, longVowels[next] == nil, marks[next] == nil, index + 1 < letters.count - 1 { result.append((.uh, 0.9)) }
        }
        return result
    }

    static let arabicConsonants: [Character: MouthShape] = [
        "ب": .m, "م": .m, "ف": .f, "ل": .l, "و": .wOo, "ر": .r, "س": .s, "ص": .s, "ز": .s, "ش": .s, "ج": .s
    ]

    static func spelledNumber(_ digits: String) -> String {
        let names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return digits.compactMap { $0.wholeNumberValue.map { names[$0] } }.joined()
    }
}

/// Automatic lip sync: spoken words → mouth-shape keys (and jaw / width keys) on a character.
public enum LipSync {
    public struct Shape: Hashable, Sendable {
        public var time: Double
        /// One of the 14 shapes (Character Animator's set).
        public var mouth: MouthShape

        public init(time: Double, mouth: MouthShape) {
            self.time = time
            self.mouth = mouth
        }

        /// The nearest of the nine Rhubarb shapes.
        public var viseme: Viseme { mouth.viseme }
    }

    /// Mouth shapes over time for `words`. Words the phonemizer can't read fall back to `loudness`
    /// (per-frame 0…1 at `fps`): open when loud, closed when quiet. Pauses rest the mouth.
    public static func shapes(for words: [TimelineWord], language: String, loudness: [Double] = [], fps: Int = 30,
                              phonemizer: Phonemizer = .shared) -> [Shape] {
        var result: [Shape] = []
        for (index, word) in words.enumerated() {
            let duration = max(word.end - word.start, 0.04)
            var parts = phonemizer.shapes(for: word.text, language: language)
            if parts.isEmpty {
                parts = loudnessShapes(from: word.start, to: word.end, loudness: loudness, fps: fps)
            }
            // Don't show more than ~15 shapes a second: merge tiny phonemes into their neighbours.
            let maxShapes = max(Int(duration * 15), 1)
            if parts.count > maxShapes { parts = thin(parts, to: maxShapes) }
            let total = parts.reduce(0) { $0 + $1.1 }
            var time = word.start
            for (shape, weight) in parts {
                if result.last?.mouth != shape { result.append(Shape(time: time, mouth: shape)) }
                time += duration * weight / max(total, 1e-9)
            }
            // Rest in pauses (not between words spoken together).
            let nextStart = index + 1 < words.count ? words[index + 1].start : .infinity
            if nextStart - word.end > 0.18 { result.append(Shape(time: word.end, mouth: .neutral)) }
        }
        return result
    }

    static func thin<T>(_ parts: [(T, Double)], to count: Int) -> [(T, Double)] {
        var parts = parts
        while parts.count > count {
            let index = parts.indices.min { parts[$0].1 < parts[$1].1 } ?? 0
            let neighbour = index + 1 < parts.count ? index + 1 : index - 1
            parts[neighbour].1 += parts[index].1
            parts.remove(at: index)
        }
        return parts
    }

    /// Open/closed from the voice's loudness (the fallback for words without known sounds).
    static func loudnessShapes(from start: Double, to end: Double, loudness: [Double], fps: Int) -> [(MouthShape, Double)] {
        guard !loudness.isEmpty, fps > 0 else { return [(.uh, 1), (.d, 1)] }
        let first = max(Int(start * Double(fps)), 0)
        let last = min(Int(end * Double(fps)), loudness.count - 1)
        guard last >= first else { return [(.uh, 1)] }
        return (first ... last).map { frame in
            let level = loudness[frame]
            let shape: MouthShape = level > 0.65 ? .ah : (level > 0.35 ? .uh : (level > 0.12 ? .d : .m))
            return (shape, 1)
        }
    }

    /// Keys on `character`: `mouthShape` (the 14, stepped), `mouth` (the nine, stepped) and `jawOpen` and `mouthWide`
    /// (eased), replacing keys of those properties inside the spoken range. One command, one undo step.
    public static func keys(_ shapes: [Shape], character: ObjectID, range: TimeRange, timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard !shapes.isEmpty else { return nil }
        var edits: [TrackEdit] = []
        let plan: [(PropertyKey, (MouthShape) -> PropertyValue, Easing)] = [
            (.mouthShape, { .enumeration($0.rawValue) }, .step),
            (.mouth, { .enumeration($0.viseme.rawValue) }, .step),
            (.jawOpen, { .float($0.viseme.jaw) }, .easeInOut),
            (.mouthWide, { .float($0.viseme.width) }, .easeInOut)
        ]
        for (property, value, easing) in plan {
            var track = timeline.track(for: character, property) ?? Track(id: ids.next(), target: character, property: property)
            track.removeKeys(in: range)
            for shape in shapes where range.contains(shape.time, tolerance: 1e-6) {
                track.setKey(Keyframe(time: shape.time, value: value(shape.mouth), easing: easing))
            }
            // Rest after the last word.
            track.setKey(Keyframe(time: range.end, value: value(.neutral), easing: easing))
            edits.append(TrackEdit(track))
        }
        return .batch("Lip sync", [.setTracks(edits)])
    }
}
