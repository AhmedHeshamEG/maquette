import Foundation

/// What a part of a made character is for (K1, CONTEXT §10.11). Every part is optional and repeatable; the job is what
/// the app knows about it: where it goes, how it's rigged and which face states it has. A part is a thing like any
/// other (a shape from the set, a drawing, something modelled), with its job on `SceneObject.part`.
public struct CharacterPart: Codable, Hashable, Sendable {
    public enum Job: String, Codable, Sendable, CaseIterable, Identifiable {
        case head, eye, brow, mouth, nose, ear, hair, body, arm, leg, tail, wing, extra

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .head: "Head"
            case .eye: "Eyes"
            case .brow: "Brows"
            case .mouth: "Mouth"
            case .nose: "Nose"
            case .ear: "Ears"
            case .hair: "Hair"
            case .body: "Body"
            case .arm: "Arms"
            case .leg: "Legs"
            case .tail: "Tail"
            case .wing: "Wings"
            case .extra: "Extras"
            }
        }

        public var systemImage: String {
            switch self {
            case .head: "circle"
            case .eye: "eye"
            case .brow: "eyebrow"
            case .mouth: "mouth"
            case .nose: "nose"
            case .ear: "ear"
            case .hair: "scribble.variable"
            case .body: "capsule.portrait"
            case .arm: "hand.raised"
            case .leg: "figure.walk"
            case .tail: "scribble"
            case .wing: "bird"
            case .extra: "sparkles"
            }
        }

        /// Face parts sit on the head (or on whatever carries them) and have face states.
        public var isFace: Bool { [.eye, .brow, .mouth, .nose].contains(self) }

        /// Parts that come as a mirrored pair when symmetry is on.
        public var isPaired: Bool { [.eye, .brow, .ear, .arm, .leg, .wing].contains(self) }

        /// Parts made of several pieces that hinge (upper, lower, end), each riding its own joint.
        public var segments: Int {
            switch self {
            case .arm, .leg: 3
            case .tail: 4
            case .wing: 2
            default: 1
            }
        }
    }

    public enum Side: String, Codable, Sendable {
        case left, right, middle

        /// +x is the character's left (it faces +z).
        public var sign: Double {
            switch self {
            case .left: 1
            case .right: -1
            case .middle: 0
            }
        }

        public var mirror: Side {
            switch self {
            case .left: .right
            case .right: .left
            case .middle: .middle
            }
        }

        /// The suffix the face rig reads ("eye.L").
        var tag: String { self == .right ? "R" : "L" }
    }

    public var job: Job
    public var side: Side
    /// The set's style it was made from ("round", "paw"…), or "drawn" / "modelled" when it came from the Pencil or the
    /// Model tool.
    public var style: String
    /// Which piece of a hinged part (0 the upper, then down to the end); 0 for a part of one piece.
    public var segment: Int
    /// Which limb it is when there are several (legs: "front" and "back"; extra arms: "1"…); empty for the first.
    public var limb: String
    /// Face states the person changed (`FaceStates`); a state missing here is the job's default.
    public var states: [String: FaceBend]
    /// A drawing of one face state ("oh", "blink", "angry"): it shows only while its part is in that state, in place of
    /// the part. Nil for the part itself.
    public var shows: String?
    /// Areas of this piece named as parts of their own (Q2: a model made a character, its own eyes, mouth and brows).
    public var regions: [CharacterRegion]

    public init(job: Job, side: Side = .middle, style: String, segment: Int = 0, limb: String = "", states: [String: FaceBend] = [:],
                shows: String? = nil, regions: [CharacterRegion] = []) {
        self.job = job
        self.side = side
        self.style = style
        self.segment = segment
        self.limb = limb
        self.states = states
        self.shows = shows
        self.regions = regions
    }

    private enum CodingKeys: String, CodingKey { case job, side, style, segment, limb, states, shows, regions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        job = try c.decode(Job.self, forKey: .job)
        side = try c.decodeIfPresent(Side.self, forKey: .side) ?? .middle
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "modelled"
        segment = try c.decodeIfPresent(Int.self, forKey: .segment) ?? 0
        limb = try c.decodeIfPresent(String.self, forKey: .limb) ?? ""
        states = try c.decodeIfPresent([String: FaceBend].self, forKey: .states) ?? [:]
        shows = try c.decodeIfPresent(String.self, forKey: .shows)
        regions = try c.decodeIfPresent([CharacterRegion].self, forKey: .regions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(job, forKey: .job)
        if side != .middle { try c.encode(side, forKey: .side) }
        try c.encode(style, forKey: .style)
        if segment != 0 { try c.encode(segment, forKey: .segment) }
        if !limb.isEmpty { try c.encode(limb, forKey: .limb) }
        if !states.isEmpty { try c.encode(states, forKey: .states) }
        try c.encodeIfPresent(shows, forKey: .shows)
        if !regions.isEmpty { try c.encode(regions, forKey: .regions) }
    }

    /// The face rig's role for this part: eyes blink and their pupils look through it ("eye.L"). Brows and mouths bend
    /// through their face states instead (`FaceStates`), so the face rig leaves them alone.
    public var faceRole: String? {
        job == .eye ? "eye.\(side.tag)" : nil
    }

    /// The role of an eye's pupil.
    public var pupilRole: String { "pupil.\(side.tag)" }

    /// Two parts are the same limb (its pieces, or its mirror when `mirrored`).
    public func sameLimb(as other: CharacterPart, mirrored: Bool = false) -> Bool {
        job == other.job && limb == other.limb && (side == other.side || (mirrored && side == other.side.mirror))
    }
}

/// How a character was started (Library ▸ Characters ▸ New).
public enum CharacterStart: String, Codable, Sendable, CaseIterable, Identifiable {
    case person, fourLegs, wings, blob, mannequin, nothing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .person: "Person"
        case .fourLegs: "Four legs"
        case .wings: "Wings"
        case .blob: "Blob"
        case .mannequin: "Mannequin"
        case .nothing: "Nothing"
        }
    }

    public var systemImage: String {
        switch self {
        case .person: "figure.stand"
        case .fourLegs: "pawprint"
        case .wings: "bird"
        case .blob: "drop"
        case .mannequin: "figure.arms.open"
        case .nothing: "circle.dashed"
        }
    }
}

public extension PropertyKey {
    /// On a made character's group: how it was started (`CharacterStart`). Its presence is what makes a group a character
    /// the maker looks after (it rigs itself again whenever its parts change).
    static let characterStart: PropertyKey = "characterStart"
    /// On a character: which of the 14 mouth shapes shows (`MouthShape`), keyed by lip sync beside `mouth`.
    static let mouthShape: PropertyKey = "mouthShape"
    /// On a character: the brows' state (`BrowState`), keyed or set by a trigger.
    static let browState: PropertyKey = "browState"
}
