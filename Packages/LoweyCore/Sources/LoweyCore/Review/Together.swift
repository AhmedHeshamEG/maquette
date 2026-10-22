import Foundation

// MARK: The iPhone companion (U8)

/// What the iPhone beside the iPad is doing for it.
public enum CompanionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case face, camera, remote, augmented, roomScan, objectScan

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .face: "Your face"
        case .camera: "Camera"
        case .remote: "Remote"
        case .augmented: "See it in AR"
        case .roomScan: "Scan a room"
        case .objectScan: "Scan an object"
        }
    }

    public var systemImage: String {
        switch self {
        case .face: "face.smiling"
        case .camera: "video"
        case .remote: "playpause"
        case .augmented: "arkit"
        case .roomScan: "house"
        case .objectScan: "cube.transparent"
        }
    }

    /// What it does, in a line.
    public var subtitle: String {
        switch self {
        case .face: "Your face and arms drive a character"
        case .camera: "Move the iPhone: the scene's camera follows"
        case .remote: "Play, skip shots and walk while presenting"
        case .augmented: "The scene, life size or on the table"
        case .roomScan: "Walls, doors, windows and furniture"
        case .objectScan: "Walk round a thing to make it a model"
        }
    }
}

/// What this iPhone can do (asked once, sent when it joins).
public struct CompanionAbilities: Codable, Hashable, Sendable {
    public var faceTracking: Bool
    public var worldTracking: Bool
    public var roomScan: Bool
    public var objectScan: Bool

    public init(faceTracking: Bool = false, worldTracking: Bool = false, roomScan: Bool = false, objectScan: Bool = false) {
        self.faceTracking = faceTracking
        self.worldTracking = worldTracking
        self.roomScan = roomScan
        self.objectScan = objectScan
    }

    public func can(_ mode: CompanionMode) -> Bool {
        switch mode {
        case .face: faceTracking
        case .camera, .augmented: worldTracking
        case .remote: true
        case .roomScan: roomScan
        case .objectScan: objectScan
        }
    }
}

/// The iPhone's buttons and sticks while the iPad presents.
public enum RemoteCommand: Codable, Hashable, Sendable {
    case playPause
    case previousShot
    case nextShot
    case fromTheStart
    /// Walking: the left stick moves (x right, y forward), the right one looks (x right, y up); each −1…1.
    case walk(moveX: Double, moveY: Double, lookX: Double, lookY: Double)
    case endPresenting
}

/// What the remote shows about the presentation.
public struct PresentStatus: Codable, Hashable, Sendable {
    public var playing: Bool
    public var walking: Bool
    /// The shot's camera name, and which shot of how many.
    public var shot: String?
    public var shotIndex: Int
    public var shotCount: Int

    public init(playing: Bool = false, walking: Bool = false, shot: String? = nil, shotIndex: Int = 0, shotCount: Int = 0) {
        self.playing = playing
        self.walking = walking
        self.shot = shot
        self.shotIndex = shotIndex
        self.shotCount = shotCount
    }
}

/// One message on the companion link (framed JSON, `HmmLink`).
public enum CompanionMessage: Codable, Sendable {
    // The iPhone to the iPad.
    case hello(name: String, abilities: CompanionAbilities)
    /// The iPhone's motion since its camera started, as a local move of the scene's camera.
    case cameraPose(Transform)
    case remote(RemoteCommand)
    case roomScan(RoomScan)
    /// An object scan made into a USDZ model on the iPhone.
    case objectScan(name: String, model: Data)
    /// Something went wrong on the iPhone, in words.
    case trouble(String)

    // The iPad to the iPhone.
    /// The iPad wants the iPhone in this mode (it switches by itself).
    case ask(CompanionMode)
    case presenting(PresentStatus)
    /// The scene as a USDZ model, for AR.
    case model(name: String, data: Data)
    /// The iPad no longer needs the iPhone; it goes back to its list.
    case done

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) -> CompanionMessage? { try? JSONDecoder().decode(Self.self, from: data) }
}

// MARK: Review over FaceTime (U8)

/// One message between the people reviewing a project together (SharePlay).
public enum ReviewMessage: Codable, Sendable {
    /// Who joined.
    case hello(name: String)
    /// The view someone is turning to; `sequence` orders a sender's views (the quick channel may reorder them).
    case view(Viewpoint, from: String, sequence: Int)
    /// Notes written, answered, resolved or deleted.
    case notes([NoteEdit])
    /// The playhead, for a film being reviewed.
    case time(Double, playing: Bool, from: String)

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) -> ReviewMessage? { try? JSONDecoder().decode(Self.self, from: data) }
}

/// Who turns the view in a review: whoever moved it last. While this device's person is moving it, views from the
/// others wait until they've been still for a moment, so two people never fight over the camera; a view older than
/// one already shown from the same person is dropped.
public struct ViewLead: Sendable {
    /// How long after the last local move a remote view is taken again.
    public var quiet: Double
    private var lastLocal = -Double.infinity
    private var newest: [String: Int] = [:]

    public init(quiet: Double = 0.6) {
        self.quiet = quiet
    }

    /// This device's person moved the view at `time`.
    public mutating func movedHere(at time: Double) {
        lastLocal = time
    }

    /// Whether to show `sequence` from `sender`, arriving at `time`.
    public mutating func accepts(from sender: String, sequence: Int, at time: Double) -> Bool {
        if let seen = newest[sender], sequence <= seen { return false }
        newest[sender] = sequence
        return time - lastLocal >= quiet
    }
}

// MARK: Present mode (U8)

/// The film's shots for presenting: where each starts (its camera cuts), and stepping between them.
public struct PresentPlan: Sendable, Equatable {
    public struct Shot: Sendable, Equatable {
        public var start: Double
        public var camera: ObjectID?
    }

    public var shots: [Shot]
    public var duration: Double

    public init(_ timeline: Timeline) {
        let cuts = timeline.cuts.sorted { $0.time < $1.time }
        var shots: [Shot] = []
        for cut in cuts where cut.time < timeline.duration - 1e-6 {
            if let last = shots.last, abs(last.start - cut.time) < 1e-6 {
                shots[shots.count - 1].camera = cut.camera
            } else {
                shots.append(Shot(start: max(0, cut.time), camera: cut.camera))
            }
        }
        if shots.first.map({ $0.start > 1e-6 }) ?? true { shots.insert(Shot(start: 0, camera: nil), at: 0) }
        self.shots = shots
        duration = timeline.duration
    }

    /// The shot playing at `time`.
    public func index(at time: Double) -> Int {
        shots.lastIndex { $0.start <= time + 1e-6 } ?? 0
    }

    /// The next shot's start, or nil at the last.
    public func next(after time: Double) -> Double? {
        let index = index(at: time)
        return index + 1 < shots.count ? shots[index + 1].start : nil
    }

    /// Back: to the start of this shot, or of the one before when within a second of this one's start (a remote's
    /// "previous" behaves as a music player's does).
    public func previous(before time: Double) -> Double {
        let index = index(at: time)
        if time - shots[index].start > 1 || index == 0 { return shots[index].start }
        return shots[index - 1].start
    }
}
