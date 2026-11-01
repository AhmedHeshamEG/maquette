import Foundation

/// The scene as an agent reads it (S16 item 19): every thing by name, where it is in the world, how big it is, what it
/// hangs from and what it stands on, at a moment of the timeline. Served at GET /v2/scene, the bridge's `scene_graph`.
public struct SceneGraphReport: Codable, Hashable, Sendable {
    /// The space, fixed in words: units, which way is up, which way the audience looks from.
    public var space: String
    public var time: Double
    public var things: [Thing]

    public struct Thing: Codable, Hashable, Sendable {
        public var name: String
        public var kind: String
        public var parent: String?
        /// World position (its origin: the bottom middle for shapes and models), metres.
        public var position: [Double]
        /// World turn, degrees (x, y, z).
        public var rotation: [Double]
        /// World box size and corners (nil for marks and empty groups).
        public var size: [Double]?
        public var min: [Double]?
        public var max: [Double]?
        /// What it stands on: another thing's name, "ground", or nil when it's in the air.
        public var sitsOn: String?
        public var shown: Bool
    }

    public static let space = "metres; y is up and the ground is y = 0; the audience looks from +z toward -z; x runs right"

    /// The report at `time` (the scene as it plays then). `names` limits it to those things (case-insensitive).
    public static func read(_ document: Document, library: LibraryManifest = LibraryManifest(), at time: Double, names: [String]? = nil)
        -> SceneGraphReport {
        let scene = Animator.evaluate(document, at: time).scene
        let bounds = SceneBounds(library: library)
        let wanted = names.map { Set($0.map { $0.lowercased() }) }
        let boxes = Dictionary(uniqueKeysWithValues: scene.objects.keys.compactMap { id in bounds.worldBounds(of: id, in: scene).map { (id, $0) } })
        let round = { (value: Double) in (value * 1000).rounded() / 1000 }
        let things = scene.objects.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.compactMap { object -> Thing? in
            if let wanted, !wanted.contains(object.name.lowercased()) { return nil }
            let world = scene.worldTransform(of: object.id)
            let box = boxes[object.id]
            return Thing(name: object.name, kind: kindName(object.kind), parent: object.parent.flatMap { scene.objects[$0]?.name },
                         position: [world.position.x, world.position.y, world.position.z].map(round), rotation: { let e = world.rotation.eulerDegrees; return [e.x, e.y, e.z].map(round) }(),
                         size: box.map { [$0.size.x, $0.size.y, $0.size.z].map(round) }, min: box.map { [$0.min.x, $0.min.y, $0.min.z].map(round) }, max: box.map { [$0.max.x, $0.max.y, $0.max.z].map(round) },
                         sitsOn: box.flatMap { support(of: object.id, box: $0, boxes: boxes, scene: scene) },
                         shown: ShotObserver.isShown(object.id, in: scene))
        }
        return SceneGraphReport(space: space, time: time, things: things)
    }

    static func kindName(_ kind: ObjectKind) -> String {
        switch kind {
        case let .primitive(shape): shape.rawValue
        case .group: "group"
        case .camera: "camera"
        case .light: "light"
        case .asset: "model"
        default: String(describing: kind).split(separator: "(").first.map(String.init) ?? "thing"
        }
    }

    /// The highest top under its bottom (within 2 cm) that its footprint overlaps: a thing, or the ground.
    static func support(of id: ObjectID, box: Bounds, boxes: [ObjectID: Bounds], scene: Scene) -> String? {
        var best: (height: Double, name: String)?
        for (other, below) in boxes where other != id && !scene.isAncestor(other, of: id) && !scene.isAncestor(id, of: other) {
            guard below.max.x > box.min.x, below.min.x < box.max.x, below.max.z > box.min.z, below.min.z < box.max.z,
                  abs(below.max.y - box.min.y) < 0.02, below.max.y > (best?.height ?? -.infinity),
                  let name = scene.objects[other]?.name else { continue }
            best = (below.max.y, name)
        }
        if let best { return best.name }
        return abs(box.min.y) < 0.02 ? "ground" : nil
    }
}
