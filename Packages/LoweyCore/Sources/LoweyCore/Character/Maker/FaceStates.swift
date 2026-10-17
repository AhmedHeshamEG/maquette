import Foundation

/// The 14 mouth shapes of Adobe Character Animator's set: what lip sync, the live voice and a typed line choose between.
public enum MouthShape: String, Codable, Sendable, CaseIterable, Identifiable {
    case neutral, ah, d, ee, f, l, m, oh, r, s, uh, wOo, smile, surprised

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .ah: "Ah"
        case .d: "D"
        case .ee: "Ee"
        case .f: "F"
        case .l: "L"
        case .m: "M"
        case .oh: "Oh"
        case .r: "R"
        case .s: "S"
        case .uh: "Uh"
        case .wOo: "W-Oo"
        case .smile: "Smile"
        case .surprised: "Surprised"
        }
    }

    /// The nearest of the nine Rhubarb shapes (swap sets drawn before 0.20, Blobs, jaw and width keys).
    public var viseme: Viseme {
        switch self {
        case .neutral, .smile: .X
        case .ah, .surprised: .D
        case .uh: .C
        case .d, .s, .r, .ee: .B
        case .f: .G
        case .l: .H
        case .m: .A
        case .oh: .E
        case .wOo: .F
        }
    }

    /// The shape a Rhubarb letter stands for (the live voice and words read by rules).
    public init(_ viseme: Viseme) {
        switch viseme {
        case .A: self = .m
        case .B: self = .ee
        case .C: self = .uh
        case .D: self = .ah
        case .E: self = .oh
        case .F: self = .wOo
        case .G: self = .f
        case .H: self = .l
        case .X: self = .neutral
        }
    }

    /// The dictionary's letter for a phoneme class (`Tools/make_visemes.py`): one letter per shape, lower case for vowels.
    init?(letter: Character) {
        switch letter.lowercased() {
        case "a": self = .ah
        case "d": self = .d
        case "e": self = .ee
        case "f": self = .f
        case "l": self = .l
        case "m": self = .m
        case "o": self = .oh
        case "r": self = .r
        case "s": self = .s
        case "u": self = .uh
        case "w": self = .wOo
        case "x": self = .neutral
        default: return nil
        }
    }

    /// From the face's channels when no shape is keyed (face capture, the jaw and width keys of older lip sync).
    public static func reading(jaw: Double, wide: Double, smile: Double, brows: Double) -> MouthShape {
        if jaw > 0.6, brows > 0.4 { return .surprised }
        if jaw > 0.55 { return wide < -0.2 ? .oh : .ah }
        if jaw > 0.25 { return wide < -0.4 ? .wOo : (wide > 0.35 ? .ee : .uh) }
        if smile > 0.45 { return .smile }
        if jaw > 0.08 { return wide < -0.4 ? .wOo : .d }
        return .neutral
    }
}

/// The brows' four states.
public enum BrowState: String, Codable, Sendable, CaseIterable, Identifiable {
    case neutral, up, angry, sad

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// A face state made by bending the part (K1): how far it opens, widens, rounds, smiles, lifts, tilts and squashes, in
/// the part's own size. The same bend works on any part (a shape from the set, something modelled), so a state never
/// needs a copy of the mesh, and exports turn it into a blend shape by bending the exported corners.
public struct FaceBend: Codable, Hashable, Sendable {
    /// Taller (+) or pressed shut (−) about the middle line; the lower half moves more, like a jaw.
    public var open: Double
    /// Wider (+) or narrower (−).
    public var wide: Double
    /// Puckered: narrower and pushed forward.
    public var round: Double
    /// Corners up (+) or down (−).
    public var smile: Double
    /// Up (+) or down (−) by the part's height.
    public var lift: Double
    /// The inner end down (+, angry) or up (−, sad), mirrored by side.
    public var tilt: Double
    /// Closed toward the upper edge (an eyelid): 1 is shut.
    public var squash: Double

    public init(open: Double = 0, wide: Double = 0, round: Double = 0, smile: Double = 0, lift: Double = 0, tilt: Double = 0, squash: Double = 0) {
        self.open = open
        self.wide = wide
        self.round = round
        self.smile = smile
        self.lift = lift
        self.tilt = tilt
        self.squash = squash
    }

    public static let none = FaceBend()
    public var isNone: Bool { self == .none }

    public func mixed(_ other: FaceBend, _ t: Double) -> FaceBend {
        FaceBend(open: open + (other.open - open) * t, wide: wide + (other.wide - wide) * t, round: round + (other.round - round) * t,
                 smile: smile + (other.smile - smile) * t, lift: lift + (other.lift - lift) * t, tilt: tilt + (other.tilt - tilt) * t,
                 squash: squash + (other.squash - squash) * t)
    }

    /// A point of the part bent (the part's own space; `bounds` its rest shape, `side` +1 left, −1 right, 0 middle).
    public func bend(_ point: Vec3, bounds: Bounds, side: Double) -> Vec3 {
        let centre = bounds.center
        let half = Vec3(max(bounds.size.x / 2, 1e-6), max(bounds.size.y / 2, 1e-6), max(bounds.size.z / 2, 1e-6))
        var u = (point.x - centre.x) / half.x
        var v = (point.y - centre.y) / half.y
        var w = (point.z - centre.z) / half.z
        // Open about the middle line, the lower half twice as far; pressed shut flattens toward it.
        let openBy = open >= 0 ? 1 + open * (v < 0 ? 1.6 : 0.8) : max(1 + open, 0.08)
        v *= openBy
        u *= max(1 + wide * 0.45 - round * 0.4, 0.15)
        w += round * 0.9 * max(1 - u * u, 0)
        v += smile * 0.7 * u * u - smile * 0.15
        if squash > 0 {
            // An eyelid closing from the top: everything falls toward the upper edge's line.
            let lid = 1 - min(squash, 1) * 1.9
            if v > lid { v = lid + (v - lid) * (1 - min(squash, 1)) * 0.2 }
        }
        v += lift * 2
        // The inner end is the one toward the middle of the face (−x for the left part, +x for the right).
        let inner = side == 0 ? 0 : -u * side
        v -= tilt * 0.9 * inner
        return Vec3(centre.x + u * half.x, centre.y + v * half.y, centre.z + w * half.z)
    }

    /// A whole mesh bent (positions only; normals follow).
    public func bend(_ mesh: MeshData, bounds: Bounds, side: Double) -> MeshData {
        var result = mesh
        result.positions = mesh.positions.map { p in
            let bent = bend(Vec3(Double(p.x), Double(p.y), Double(p.z)), bounds: bounds, side: side)
            return SIMD3<Float>(Float(bent.x), Float(bent.y), Float(bent.z))
        }
        if result.normals.count == result.positions.count { result.computeSmoothNormals() }
        return result
    }
}

/// The face states of each job and the bends they start from (K1 step 3); `CharacterPart.states` keeps what the person
/// changed. Mouths have Character Animator's 14, brows four, eyes open and blink (looking moves their pupils).
public enum FaceStates {
    /// Every state a job has, in the maker's order ("neutral" first; it's the part as made).
    public static func names(for job: CharacterPart.Job) -> [String] {
        switch job {
        case .mouth: MouthShape.allCases.map(\.rawValue)
        case .brow: BrowState.allCases.map(\.rawValue)
        case .eye: ["open", "blink"]
        default: []
        }
    }

    public static func title(_ state: String) -> String {
        MouthShape(rawValue: state)?.title ?? state.capitalized
    }

    /// The bend a job's state starts from.
    public static func defaultBend(_ job: CharacterPart.Job, _ state: String) -> FaceBend {
        switch job {
        case .mouth: mouthBend(MouthShape(rawValue: state) ?? .neutral)
        case .brow:
            switch BrowState(rawValue: state) ?? .neutral {
            case .neutral: .none
            case .up: FaceBend(lift: 0.45)
            case .angry: FaceBend(lift: -0.2, tilt: 0.45)
            case .sad: FaceBend(lift: 0.12, tilt: -0.4)
            }
        case .eye: state == "blink" ? FaceBend(squash: 1) : .none
        default: .none
        }
    }

    static func mouthBend(_ shape: MouthShape) -> FaceBend {
        switch shape {
        case .neutral: .none
        case .ah: FaceBend(open: 1.2, wide: 0.1)
        case .d: FaceBend(open: 0.45, wide: 0.3)
        case .ee: FaceBend(open: 0.3, wide: 0.6, smile: 0.2)
        case .f: FaceBend(open: 0.1, wide: 0.15, smile: -0.1)
        case .l: FaceBend(open: 0.6, wide: 0.05)
        case .m: FaceBend(open: -0.6, wide: 0.05)
        case .oh: FaceBend(open: 0.85, round: 0.6)
        case .r: FaceBend(open: 0.35, round: 0.35)
        case .s: FaceBend(open: 0.15, wide: 0.5)
        case .uh: FaceBend(open: 0.6, wide: -0.1)
        case .wOo: FaceBend(open: 0.25, round: 0.95)
        case .smile: FaceBend(wide: 0.35, smile: 0.85)
        case .surprised: FaceBend(open: 1.5, round: 0.35)
        }
    }

    /// A part's bend for a state: the person's own, else the default.
    public static func bend(of part: CharacterPart, _ state: String) -> FaceBend {
        part.states[state] ?? defaultBend(part.job, state)
    }

    /// The state each face part shows on a character with these channel values (`values` reads the character's).
    public static func active(_ part: CharacterPart, values: (PropertyKey) -> PropertyValue?) -> (state: String, bend: FaceBend) {
        func number(_ key: PropertyKey) -> Double { values(key)?.floatValue ?? 0 }
        switch part.job {
        case .mouth:
            let keyed = values(.mouthShape)?.stringValue.flatMap(MouthShape.init(rawValue:))
            let fromLetter = values(.mouth)?.stringValue.flatMap(Viseme.init(rawValue:)).map(MouthShape.init)
            let read = MouthShape.reading(jaw: number(.jawOpen), wide: number(.mouthWide), smile: number(.smile), brows: number(.brows))
            let shape = keyed ?? (fromLetter.flatMap { $0 == .neutral ? nil : $0 } ?? read)
            return (shape.rawValue, bend(of: part, shape.rawValue))
        case .brow:
            if let state = values(.browState)?.stringValue.flatMap(BrowState.init(rawValue:)), state != .neutral {
                return (state.rawValue, bend(of: part, state.rawValue))
            }
            // The brows channel (face capture, expressions): up or down by how much.
            let brows = number(.brows)
            if abs(brows) < 0.02 { return (BrowState.neutral.rawValue, .none) }
            let state: BrowState = brows > 0 ? .up : .angry
            return (state.rawValue, FaceBend.none.mixed(bend(of: part, state.rawValue), min(abs(brows), 1)))
        case .eye:
            // Blinking itself is the face rig's (it closes the eye part); the blink state is for a drawn blink.
            let blink = part.side == .right ? number(.blinkRight) : number(.blinkLeft)
            return (blink > 0.5 ? "blink" : "open", .none)
        default:
            return ("neutral", .none)
        }
    }
}

public extension PropertySpec {
    /// The maker's keys (K1).
    static let character: [PropertyKey: PropertySpec] = [
        .mouthShape: PropertySpec(type: .enumeration, animatable: true, label: "Mouth shape"),
        .browState: PropertySpec(type: .enumeration, animatable: true, label: "Brows"),
        .characterStart: PropertySpec(type: .enumeration, animatable: false, label: "Started from")
    ]
}
