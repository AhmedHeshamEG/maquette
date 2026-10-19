import Foundation

/// Real grounds (L2, D-489): what the floor of the world is made of, drawn by the ground's own shader from where each
/// point is, so a ground has no texture to load and no seam to see, reaches the horizon, and takes the Look's light and
/// bands like everything standing on it. The ground's colour is the material's first colour; the second is derived.
public enum GroundSurface: String, Codable, Sendable, CaseIterable, Identifiable {
    case desert, grass, snow, rock, sand, pavement, waterEdge, roomFloor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .desert: "Desert"
        case .grass: "Grass"
        case .snow: "Snow"
        case .rock: "Rock"
        case .sand: "Sand"
        case .pavement: "Pavement"
        case .waterEdge: "Water's edge"
        case .roomFloor: "Room floor"
        }
    }

    public var systemImage: String {
        switch self {
        case .desert: "sun.dust"
        case .grass: "leaf"
        case .snow: "snowflake"
        case .rock: "mountain.2"
        case .sand: "beach.umbrella"
        case .pavement: "square.grid.3x3"
        case .waterEdge: "water.waves"
        case .roomFloor: "rectangle.split.3x1"
        }
    }

    /// The colour the ground takes when it's chosen (the person can change it afterwards).
    public var color: RGBA {
        switch self {
        case .desert: .hex("#D9A86C")
        case .grass: .hex("#6E9F4E")
        case .snow: .hex("#EEF3F7")
        case .rock: .hex("#7D7770")
        case .sand: .hex("#E3CB98")
        case .pavement: .hex("#9A9893")
        case .waterEdge: .hex("#D8C08E")
        case .roomFloor: .hex("#A9784A")
        }
    }

    /// How far the ground reaches, in metres: a room is a room; the rest go to the horizon.
    public var size: Double {
        self == .roomFloor ? 12 : 80
    }

    /// Its number in Shading.metal's ground (0 is a plain floor).
    public var shaderIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? -1) + 1
    }
}

public extension Ground {
    /// The ground made of `surface` (nil: a plain floor), in its colour and reach, shown.
    func made(of surface: GroundSurface?) -> Ground {
        var ground = self
        ground.surface = surface
        ground.visible = true
        if let surface {
            ground.color = surface.color
            ground.size = surface.size
        }
        return ground
    }
}
