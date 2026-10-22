import Foundation

/// What a thing is in a building (G1): walls, floors, roofs… IFC files, plans and room areas read it. Anything without
/// one is furniture or a plain thing.
public enum BuildingPart: String, Codable, Sendable, CaseIterable {
    case wall, slab, roof, stairs, column, beam, railing, door, window, person, terrain, furniture

    public var title: String {
        switch self {
        case .wall: "Wall"
        case .slab: "Floor"
        case .roof: "Roof"
        case .stairs: "Stairs"
        case .column: "Column"
        case .beam: "Beam"
        case .railing: "Railing"
        case .door: "Door"
        case .window: "Window"
        case .person: "Person"
        case .terrain: "Terrain"
        case .furniture: "Furniture"
        }
    }

    /// Parts that close a room off (walls and columns; railings don't).
    public var encloses: Bool { self == .wall || self == .column }
}

public extension PropertyKey {
    /// What a thing is in a building (`BuildingPart`).
    static let buildingPart: PropertyKey = "buildingPart"
    /// How far a group is pulled apart, 0 together … 1 exploded (Study).
    static let explode: PropertyKey = "explode"
    /// Where a part goes when its group explodes, in the group's space (set when the group is exploded).
    static let explodeOffset: PropertyKey = "explodeOffset"
}

extension PropertySpec {
    static let guests: [PropertyKey: PropertySpec] = [
        .buildingPart: PropertySpec(type: .enumeration, animatable: false, label: "Building part"),
        .explode: PropertySpec(type: .float, animatable: true, label: "Explode"),
        .explodeOffset: PropertySpec(type: .vec3, animatable: false, label: "Exploded place")
    ]
}

public extension SceneObject {
    var buildingPart: BuildingPart? {
        get { self[.buildingPart]?.stringValue.flatMap(BuildingPart.init(rawValue:)) }
        set { self[.buildingPart] = newValue.map { .enumeration($0.rawValue) } }
    }

    var explodeAmount: Double { min(max(self[.explode]?.floatValue ?? 0, 0), 1) }
}
