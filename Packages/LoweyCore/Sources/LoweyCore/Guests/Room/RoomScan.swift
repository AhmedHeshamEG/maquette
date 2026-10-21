import Foundation

/// A scanned room (G1, Room ▸ Scan a room): what the iPad's LiDAR scan found, as plain sizes and places (the engine
/// reads Apple's RoomPlan into this), made into a building: each wall a solid with its doors, windows and openings
/// cut through it, the floor under them, and each piece of furniture a block of its size, named for what it is.
public struct RoomScan: Codable, Hashable, Sendable {
    public enum SurfaceKind: String, Codable, Sendable {
        case wall, door, window, opening, floor
    }

    public struct Surface: Codable, Hashable, Sendable {
        public var kind: SurfaceKind
        /// The middle of the surface, and how it's turned (its width along local x, its height along y, facing z).
        public var position: Vec3
        public var rotation: Quat
        public var width: Double
        public var height: Double
        /// A floor's outline, when the scan gives one (world space).
        public var corners: [Vec3]?

        public init(kind: SurfaceKind, position: Vec3, rotation: Quat, width: Double, height: Double, corners: [Vec3]? = nil) {
            self.kind = kind
            self.position = position
            self.rotation = rotation
            self.width = width
            self.height = height
            self.corners = corners
        }
    }

    public struct Item: Codable, Hashable, Sendable {
        /// What it is ("sofa", "table", "stairs"…).
        public var category: String
        public var position: Vec3
        public var rotation: Quat
        public var size: Vec3

        public init(category: String, position: Vec3, rotation: Quat, size: Vec3) {
            self.category = category
            self.position = position
            self.rotation = rotation
            self.size = size
        }
    }

    public var surfaces: [Surface]
    public var items: [Item]

    public init(surfaces: [Surface], items: [Item]) {
        self.surfaces = surfaces
        self.items = items
    }

    /// Scanned walls have no thickness; they're built this thick, centred on the scan.
    public static let wallThickness = 0.12

    /// The scan as one group of things (one undo step), with ids from `ids`.
    public func command(ids: inout IDFactory) -> EditCommand? {
        let walls = surfaces.filter { $0.kind == .wall && $0.width > 0.05 && $0.height > 0.05 }
        guard !walls.isEmpty else { return nil }
        let group: ObjectID = ids.next()
        var objects: [SceneObject] = []
        var built = walls.map { Self.box($0, depth: Self.wallThickness) }
        for opening in surfaces where [.door, .window, .opening].contains(opening.kind) {
            guard let index = Self.wall(holding: opening, among: walls) else { continue }
            let block = Self.box(opening, depth: Self.wallThickness + 0.2)
            if let cut = try? MeshBoolean.combine(built[index], block, .subtract) { built[index] = cut }
        }
        for (index, mesh) in built.enumerated() {
            var wall = ModelingOperations.newSolid(mesh, id: ids.next())
            wall.name = "Wall \(index + 1)"
            wall.buildingPart = .wall
            wall.parent = group
            objects.append(wall)
        }
        if let floor = floorOutline(walls: walls), let slab = try? Architecture.slab(outline: floor, thickness: 0.1) {
            var object = ModelingOperations.newSolid(slab, id: ids.next())
            object.name = "Floor"
            object.buildingPart = .slab
            object.parent = group
            objects.append(object)
        }
        for item in items where item.size.minComponent > 0.01 {
            let mesh = EditableMesh.box(min: item.size * -0.5, max: item.size * 0.5)
            var object = SceneObject(id: ids.next(), name: Self.title(item.category), kind: .mesh(mesh),
                                     transform: Transform(position: item.position, rotation: item.rotation))
            object.buildingPart = item.category == "stairs" ? .stairs : .furniture
            object[.color] = .color(.rgba(Self.color(item.category)))
            object.parent = group
            objects.append(object)
        }
        var root = SceneObject(id: group, name: "Scanned room", kind: .group)
        root.children = objects.map(\.id)
        return .batch("Scan a room", [.insert(SceneFragment(objects: [root] + objects, roots: [group]), parent: nil, index: nil)])
    }

    /// A surface as a block `depth` thick, in world space.
    static func box(_ surface: Surface, depth: Double) -> EditableMesh {
        let local = EditableMesh.box(min: Vec3(-surface.width / 2, -surface.height / 2, -depth / 2),
                                     max: Vec3(surface.width / 2, surface.height / 2, depth / 2))
        return local.transformed(by: Transform(position: surface.position, rotation: surface.rotation))
    }

    /// The wall an opening sits in: the nearest whose plane it lies on and whose width it's within.
    static func wall(holding opening: Surface, among walls: [Surface]) -> Int? {
        var best: (Int, Double)?
        for (index, wall) in walls.enumerated() {
            let normal = wall.rotation.act(.unitZ), along = wall.rotation.act(.unitX)
            let offset = opening.position - wall.position
            let off = abs(offset.dot(normal)), across = abs(offset.dot(along))
            guard off < 0.3, across < wall.width / 2 + 0.05 else { continue }
            if best == nil || off < best?.1 ?? .infinity { best = (index, off) }
        }
        return best?.0
    }

    /// The scanned floor's outline, else the walls' feet in order round their middle.
    func floorOutline(walls: [Surface]) -> [Vec3]? {
        if let corners = surfaces.first(where: { $0.kind == .floor })?.corners, corners.count >= 3 { return corners }
        let feet = walls.flatMap { wall -> [Vec3] in
            let along = wall.rotation.act(.unitX) * (wall.width / 2)
            let foot = wall.position - Vec3(0, wall.height / 2, 0)
            return [foot - along, foot + along]
        }
        guard feet.count >= 3 else { return nil }
        let hull = RoomParts.convexHull(feet.map { Vec2($0.x, $0.z) })
        let floor = feet.map(\.y).min() ?? 0
        return hull.count >= 3 ? hull.map { Vec3($0.x, floor, $0.y) } : nil
    }

    static func title(_ category: String) -> String {
        switch category {
        case "washerDryer": "Washer"
        case "television": "Television"
        default: category.prefix(1).uppercased() + category.dropFirst()
        }
    }

    static func color(_ category: String) -> RGBA {
        switch category {
        case "sofa", "chair", "bed": RGBA.hex("#C9A27E")
        case "table", "storage": RGBA.hex("#A67C52")
        case "refrigerator", "stove", "oven", "dishwasher", "washerDryer": RGBA.hex("#D8D8DC")
        case "sink", "toilet", "bathtub": RGBA.hex("#F2F2F4")
        case "television", "fireplace": RGBA.hex("#3A3A3C")
        default: RGBA.hex("#B8B2A7")
        }
    }
}
