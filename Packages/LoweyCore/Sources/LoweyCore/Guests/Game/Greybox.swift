import Foundation

/// The greybox kit (G1, Game: Dev's level on the couch): pieces on a one-metre module that snap edge to edge on the
/// Game set-up's metre grid, in the flat developer colours levels are blocked out in. Each piece's middle sits on a
/// whole metre (its sides on whole metres too), so placing them on the grid lines them up.
public enum GreyboxPiece: String, CaseIterable, Sendable, Codable, Identifiable {
    case floor, tile, wall, doorway, window, ramp, stairs, block, pillar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .floor: "Floor 4 × 4"
        case .tile: "Floor 2 × 2"
        case .wall: "Wall"
        case .doorway: "Doorway"
        case .window: "Window wall"
        case .ramp: "Ramp"
        case .stairs: "Stairs"
        case .block: "Block"
        case .pillar: "Pillar"
        }
    }

    public var systemImage: String {
        switch self {
        case .floor, .tile: "square.grid.2x2"
        case .wall: "rectangle.portrait"
        case .doorway: "door.left.hand.open"
        case .window: "window.vertical.closed"
        case .ramp: "triangle"
        case .stairs: "stairs"
        case .block: "cube"
        case .pillar: "rectangle.portrait.on.rectangle.portrait"
        }
    }

    /// Floors grey-blue, walls light, ways up orange (where the player climbs), blocks blue, pillars grey.
    public var color: RGBA {
        switch self {
        case .floor, .tile: RGBA.hex("#8E9AAF")
        case .wall, .doorway, .window: RGBA.hex("#C9CED6")
        case .ramp, .stairs: RGBA.hex("#F28F3B")
        case .block: RGBA.hex("#6C8EBF")
        case .pillar: RGBA.hex("#A0A7B4")
        }
    }

    var part: BuildingPart? {
        switch self {
        case .floor, .tile: .slab
        case .wall, .doorway, .window: .wall
        case .stairs: .stairs
        case .pillar: .column
        case .ramp, .block: nil
        }
    }

    /// The piece standing on the origin, its middle there.
    public func mesh() -> EditableMesh {
        switch self {
        case .floor: return .box(min: Vec3(-2, -0.2, -2), max: Vec3(2, 0, 2))
        case .tile: return .box(min: Vec3(-1, -0.2, -1), max: Vec3(1, 0, 1))
        case .wall: return .box(min: Vec3(-2, 0, -0.125), max: Vec3(2, 3, 0.125))
        case .doorway, .window:
            let wall = EditableMesh.box(min: Vec3(-2, 0, -0.125), max: Vec3(2, 3, 0.125))
            let hole = self == .doorway ? EditableMesh.box(min: Vec3(-0.6, -0.1, -0.5), max: Vec3(0.6, 2.2, 0.5))
                : EditableMesh.box(min: Vec3(-0.6, 1, -0.5), max: Vec3(0.6, 2.2, 0.5))
            return (try? MeshBoolean.combine(wall, hole, .subtract)) ?? wall
        case .ramp:
            // Four metres long, rising a metre, two wide.
            let side = [Vec3(-1, 0, 2), Vec3(-1, 0, -2), Vec3(-1, 1, -2)]
            return Prism.make(outline: EditableMesh.newellVector(side).x > 0 ? side : side.reversed(), holes: [], normal: .unitX, from: 0, to: 2)
        case .stairs:
            return Architecture.stairs(Architecture.Stairs(rise: 1, width: 2, stepHeight: 0.25, stepDepth: 1), from: Vec3(0, 0, 2),
                                       direction: Vec3(0, 0, -1))
        case .block: return .box(min: Vec3(-1, 0, -1), max: Vec3(1, 1, 1))
        case .pillar: return .box(min: Vec3(-0.25, 0, -0.25), max: Vec3(0.25, 3, 0.25))
        }
    }
}

public extension ModelingOperations {
    /// A greybox piece with its middle at `point` (snapped to the metre grid).
    static func addGreybox(_ piece: GreyboxPiece, at point: Vec3, id: ObjectID) -> EditCommand {
        let snapped = Vec3(point.x.rounded(), max(point.y, 0).rounded(), point.z.rounded())
        var object = SceneObject(id: id, name: piece.title, kind: .mesh(piece.mesh()), transform: Transform(position: snapped))
        object[.color] = .color(.rgba(piece.color))
        object.buildingPart = piece.part
        return .batch(piece.title, [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    /// Freeze transforms: each modelled thing's turn and size baked into its shape, leaving it unturned at size one
    /// where it stands (what game engines want of a level's pieces).
    static func freezeTransforms(_ ids: [ObjectID], in scene: Scene) -> EditCommand? {
        var commands: [EditCommand] = []
        for id in ids {
            guard let object = scene.objects[id], object.children.isEmpty, canModel(object), let local = editableMesh(of: object) else { continue }
            let transform = object.transform
            guard transform.rotation != .identity || transform.scale != .one else { continue }
            let baked = local.transformed(by: Transform(rotation: transform.rotation, scale: transform.scale))
            commands.append(.setKind(id, .mesh(baked)))
            commands.append(.setProperties([PropertyChange(object: id, key: .rotation, value: .quat(.identity)),
                                            PropertyChange(object: id, key: .scale, value: .vec3(.one))]))
        }
        return commands.isEmpty ? nil : .batch("Freeze transforms", commands)
    }
}
