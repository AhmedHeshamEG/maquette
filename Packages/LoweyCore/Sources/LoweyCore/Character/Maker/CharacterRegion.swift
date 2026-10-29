import Foundation

/// A part of a model made a character that isn't a piece of its own (Q2 step 3): its eye, mouth or brow, circled with
/// the Pencil and named. It's a box in the model's own space around that area, so the model stays whole and paintable,
/// and the region outlives the model being remeshed, sculpted or cut finer for its rig (vertex numbers wouldn't). Face
/// states bend what's inside the box, fading to nothing at its edges, so the surface never tears.
public struct CharacterRegion: Codable, Hashable, Sendable {
    public var job: CharacterPart.Job
    public var side: CharacterPart.Side
    /// The box in the model's own space; the area named sits in its inner part, the rest is the fade.
    public var bounds: Bounds
    /// Face states the person changed; a state missing here is the job's default (as for a part).
    public var states: [String: FaceBend]

    public init(job: CharacterPart.Job, side: CharacterPart.Side = .middle, bounds: Bounds, states: [String: FaceBend] = [:]) {
        self.job = job
        self.side = side
        self.bounds = bounds
        self.states = states
    }

    private enum CodingKeys: String, CodingKey { case job, side, bounds, states }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        job = try c.decode(CharacterPart.Job.self, forKey: .job)
        side = try c.decodeIfPresent(CharacterPart.Side.self, forKey: .side) ?? .middle
        bounds = try c.decode(Bounds.self, forKey: .bounds)
        states = try c.decodeIfPresent([String: FaceBend].self, forKey: .states) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(job, forKey: .job)
        if side != .middle { try c.encode(side, forKey: .side) }
        try c.encode(bounds, forKey: .bounds)
        if !states.isEmpty { try c.encode(states, forKey: .states) }
    }

    /// The region read as a part, so it has the same face states as a part with its job.
    public var part: CharacterPart {
        CharacterPart(job: job, side: side, style: "region", states: states)
    }

    /// The jobs a region can have: the ones with face states.
    public static let jobs: [CharacterPart.Job] = [.eye, .mouth, .brow]

    /// The region around the points of the surface that were circled (the model's own space): the area itself in the
    /// box's inner part, room around it for the fade, and enough depth to hold the surface there but not the far side.
    public static func around(_ points: [Vec3], job: CharacterPart.Job, side: CharacterPart.Side) -> CharacterRegion? {
        guard points.count >= 3, let area = Bounds(points: points) else { return nil }
        let reach = max(area.size.x, area.size.y, 1e-4)
        let half = Vec3(max(area.size.x, reach * 0.3) / 2 / innerShare,
                        max(area.size.y, reach * 0.3) / 2 / innerShare,
                        max(area.size.z / 2 / innerShare, reach * 0.35))
        return CharacterRegion(job: job, side: side, bounds: Bounds(min: area.center - half, max: area.center + half))
    }

    /// The share of the box (from its middle) that bends fully; past it the bend fades to nothing at the edge.
    static let innerShare = 0.55

    /// How much a point follows the bend: 1 in the inner part, 0 at and beyond the box's edge.
    public func weight(_ point: Vec3) -> Double {
        let centre = bounds.center
        let half = bounds.size / 2
        let d = max(abs(point.x - centre.x) / max(half.x, 1e-9), abs(point.y - centre.y) / max(half.y, 1e-9),
                    abs(point.z - centre.z) / max(half.z, 1e-9))
        guard d < 1 else { return 0 }
        guard d > Self.innerShare else { return 1 }
        let t = (d - Self.innerShare) / (1 - Self.innerShare)
        return 1 - t * t * (3 - 2 * t)
    }
}

/// One region's bend at a moment.
public struct FaceRegionBend: Hashable, Sendable {
    public var region: CharacterRegion
    public var bend: FaceBend
}

/// The named regions of models made characters, bent by their face states (Q2 step 3). The bends travel with the frame
/// (`SimulatedShapes.regions`) and the renderer moves the model's own corners by them before its rig and its paint, so
/// a skinned, painted model blinks and talks with its own geometry.
public enum FaceRegions {
    /// Every model with a region away from rest, and its regions' bends.
    public static func bends(in scene: Scene) -> [ObjectID: [FaceRegionBend]] {
        var result: [ObjectID: [FaceRegionBend]] = [:]
        for (id, object) in scene.objects {
            guard let regions = object.part?.regions, !regions.isEmpty, let root = CharacterMaker.character(of: id, in: scene),
                  let character = scene.objects[root] else { continue }
            let bends = regions.map { FaceRegionBend(region: $0, bend: active($0, values: { character[$0] })) }.filter { !$0.bend.isNone }
            if !bends.isEmpty { result[id] = bends }
        }
        return result
    }

    /// A region's bend for its character's channel values: an eye closes as far as it blinks, a mouth and brows show
    /// their face states.
    public static func active(_ region: CharacterRegion, values: (PropertyKey) -> PropertyValue?) -> FaceBend {
        guard region.job == .eye else { return FaceStates.active(region.part, values: values).bend }
        let left = values(.blinkLeft)?.floatValue ?? 0, right = values(.blinkRight)?.floatValue ?? 0
        let blink = min(max(region.side == .right ? right : region.side == .left ? left : max(left, right), 0), 1)
        guard blink > 0.01 else { return .none }
        return FaceBend.none.mixed(FaceStates.bend(of: region.part, "blink"), blink)
    }

    /// A mesh with its regions bent (positions only, the same corners in the same order; normals follow).
    public static func bend(_ mesh: MeshData, _ bends: [FaceRegionBend]) -> MeshData {
        guard !bends.isEmpty else { return mesh }
        var result = mesh
        result.positions = mesh.positions.map { position in
            let point = Vec3(Double(position.x), Double(position.y), Double(position.z))
            var moved = point
            for item in bends {
                let weight = item.region.weight(point)
                guard weight > 0 else { continue }
                moved += (item.bend.bend(point, bounds: item.region.bounds, side: item.region.side.sign) - point) * weight
            }
            return SIMD3<Float>(Float(moved.x), Float(moved.y), Float(moved.z))
        }
        if result.normals.count == result.positions.count { result.computeSmoothNormals() }
        return result
    }
}
