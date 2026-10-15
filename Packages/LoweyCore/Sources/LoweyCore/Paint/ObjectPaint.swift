import Foundation

/// How a paint layer mixes with the layers under it (the W3C compositing formulas, in the stored sRGB values, as
/// Procreate mixes them).
public enum PaintBlend: String, Codable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, add, darken, lighten, softLight

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .add: "Add"
        case .darken: "Darken"
        case .lighten: "Lighten"
        case .softLight: "Soft light"
        }
    }

    /// The blend function on one channel (backdrop, source).
    public func mix(_ backdrop: Double, _ source: Double) -> Double {
        switch self {
        case .normal: source
        case .multiply: backdrop * source
        case .screen: backdrop + source - backdrop * source
        case .overlay: backdrop <= 0.5 ? 2 * backdrop * source : 1 - 2 * (1 - backdrop) * (1 - source)
        case .add: min(backdrop + source, 1)
        case .darken: min(backdrop, source)
        case .lighten: max(backdrop, source)
        case .softLight: Self.softLight(backdrop, source)
        }
    }

    /// The W3C soft light.
    static func softLight(_ b: Double, _ s: Double) -> Double {
        if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
        let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
        return b + (2 * s - 1) * (d - b)
    }

    /// Its number in Paint.metal's compose pass.
    public var shaderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// A square tile of a layer: `column`, `row` from the texture's top left, `PaintSurface.tileSize` pixels a side.
public struct PaintTileIndex: Hashable, Sendable, Comparable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// The key in `PaintLayer.tiles` ("column,row").
    public var key: String { "\(column),\(row)" }

    public init?(key: String) {
        let parts = key.split(separator: ",")
        guard parts.count == 2, let column = Int(parts[0]), let row = Int(parts[1]), column >= 0, row >= 0 else { return nil }
        self.init(column: column, row: row)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// One layer of paint on an object. Its pixels are tiles: PNG files in the project's assets, named by their content,
/// so a stroke changes a few small names and undo swaps them back. `tiles` is its colour; its other maps (roughness,
/// metal, glow, bumps, fur) and its mask have tiles of their own in `maps` (D-338). A fill layer's tiles are made from
/// its `fill` (D-340).
public struct PaintLayer: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var opacity: Double
    public var blend: PaintBlend
    public var visible: Bool
    /// "column,row" → the tile's file (`paint/<hash>.png` under assets). A missing tile is transparent.
    public var tiles: [String: String]
    /// A map's raw value → its tiles, as `tiles`. A `mask` here (even with no tiles) hides the layer where it's clear.
    public var maps: [String: [String: String]]
    /// What a fill layer is made of; nil for a layer painted by hand.
    public var fill: PaintFill?

    public init(id: String, name: String, opacity: Double = 1, blend: PaintBlend = .normal, visible: Bool = true, tiles: [String: String] = [:],
                maps: [String: [String: String]] = [:], fill: PaintFill? = nil) {
        self.id = id
        self.name = name
        self.opacity = min(max(opacity, 0), 1)
        self.blend = blend
        self.visible = visible
        self.tiles = tiles
        self.maps = maps
        self.fill = fill
    }

    public subscript(tile: PaintTileIndex) -> String? {
        get { tiles[tile.key] }
        set { tiles[tile.key] = newValue }
    }

    /// One map's tile (colour is `tiles`).
    public subscript(map: PaintMap, tile: PaintTileIndex) -> String? {
        get { tiles(of: map)[tile.key] }
        set {
            if map == .color {
                tiles[tile.key] = newValue
            } else {
                maps[map.rawValue, default: [:]][tile.key] = newValue
                // A map without tiles is no map; a mask without tiles still hides everything.
                if map != .mask, maps[map.rawValue]?.isEmpty == true { maps[map.rawValue] = nil }
            }
        }
    }

    /// One map's tiles (empty when it has none).
    public func tiles(of map: PaintMap) -> [String: String] {
        map == .color ? tiles : maps[map.rawValue] ?? [:]
    }

    /// The maps that hold paint (colour first), the mask left out.
    public var paintedMaps: [PaintMap] {
        PaintMap.channels.filter { !tiles(of: $0).isEmpty }
    }

    public var hasMask: Bool { maps[PaintMap.mask.rawValue] != nil }

    /// Nothing painted in any map.
    public var isEmpty: Bool { tiles.isEmpty && PaintMap.channels.allSatisfy { tiles(of: $0).isEmpty } }

    /// Every file its tiles name, in every map and the mask.
    public var files: Set<String> {
        Set(tiles.values).union(maps.values.flatMap(\.values))
    }
}

extension PaintLayer: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, opacity, blend, visible, tiles, maps, fill
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(String.self, forKey: .id), name: c.decode(String.self, forKey: .name),
                      opacity: c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1, blend: c.decodeIfPresent(PaintBlend.self, forKey: .blend) ?? .normal,
                      visible: c.decodeIfPresent(Bool.self, forKey: .visible) ?? true, tiles: c.decodeIfPresent([String: String].self, forKey: .tiles) ?? [:],
                      maps: c.decodeIfPresent([String: [String: String]].self, forKey: .maps) ?? [:],
                      fill: c.decodeIfPresent(PaintFill.self, forKey: .fill))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(blend, forKey: .blend)
        try c.encode(visible, forKey: .visible)
        try c.encode(tiles, forKey: .tiles)
        if !maps.isEmpty { try c.encode(maps, forKey: .maps) }
        try c.encodeIfPresent(fill, forKey: .fill)
    }
}

/// The surface an object is painted on: its unwrap (a file under assets) and the mesh it was made for.
public struct PaintSurface: Codable, Hashable, Sendable {
    /// Pixels a side of every layer.
    public var size: Int
    /// The unwrap's file (`paint/<hash>.uv` under assets; `PaintUnwrap`'s binary form).
    public var unwrap: String
    /// The fingerprint of the mesh the unwrap was made for (`PaintMesh.fingerprint`). When the object's mesh changes
    /// (modelling, a bevel), the paint is carried onto the new one by position.
    public var mesh: String
    /// Edges marked by hand where the unwrap must cut, in the object's own space (D-349). Nil: the unwrapper's own.
    public var seams: [PaintSeam]?

    public static let tileSize = 256
    public static let defaultSize = 2048
    /// The sizes a thing's texture can be (Surface ▸ Texture size).
    public static let sizes = [512, 1024, 2048, 4096]

    public init(size: Int = PaintSurface.defaultSize, unwrap: String, mesh: String, seams: [PaintSeam]? = nil) {
        self.size = max(Self.tileSize, size / Self.tileSize * Self.tileSize)
        self.unwrap = unwrap
        self.mesh = mesh
        self.seams = seams.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Tiles a side.
    public var tilesPerSide: Int { size / Self.tileSize }

    public var allTiles: [PaintTileIndex] {
        (0 ..< tilesPerSide).flatMap { row in (0 ..< tilesPerSide).map { PaintTileIndex(column: $0, row: row) } }
    }
}

/// Paint on an object (CONTEXT §10.4): a surface and layers, bottom first, each with its maps.
public struct ObjectPaint: Codable, Hashable, Sendable {
    public var surface: PaintSurface
    public var layers: [PaintLayer]
    /// Strokes are painted again mirrored across this axis of the object's own space (D-347).
    public var mirror: PaintMirror?
    /// A normal map baked from a more detailed surface (`paint/<hash>.png`, tangent space, D-352), and that surface's name.
    public var normalMap: String?
    public var normalsFrom: String?

    public static let maximumLayers = 16

    public init(surface: PaintSurface, layers: [PaintLayer], mirror: PaintMirror? = nil, normalMap: String? = nil, normalsFrom: String? = nil) {
        self.surface = surface
        self.layers = layers
        self.mirror = mirror
        self.normalMap = normalMap
        self.normalsFrom = normalsFrom
    }

    public func layer(_ id: String) -> PaintLayer? {
        layers.first { $0.id == id }
    }

    public func layerIndex(_ id: String) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Whether anything shows: a visible layer with a tile, or baked normals.
    public var showsPaint: Bool {
        normalMap != nil || layers.contains { $0.visible && $0.opacity > 0 && !$0.isEmpty }
    }

    /// Whether a visible layer paints this map.
    public func shows(_ map: PaintMap) -> Bool {
        layers.contains { $0.visible && $0.opacity > 0 && !$0.tiles(of: map).isEmpty }
    }

    /// The maps any visible layer paints, colour first.
    public var shownMaps: [PaintMap] {
        PaintMap.channels.filter(shows)
    }

    /// Every file the paint refers to (the unwrap, every tile of every map, the normal map), for copying a project's
    /// paint along.
    public var files: Set<String> {
        Set(layers.flatMap(\.files)).union([surface.unwrap]).union(normalMap.map { [$0] } ?? [])
    }

    /// A new layer's id, unused in this paint.
    public func newLayerID() -> String {
        var number = layers.count + 1
        while layer("l\(number)") != nil {
            number += 1
        }
        return "l\(number)"
    }

    /// A new layer's name ("Layer 3").
    public func newLayerName() -> String {
        var number = layers.count + 1
        while layers.contains(where: { $0.name == "Layer \(number)" }) {
            number += 1
        }
        return "Layer \(number)"
    }
}

/// One tile of one map of one layer set to a file (nil = transparent). `map` is nil for colour.
public struct PaintTileChange: Codable, Hashable, Sendable {
    public var layer: String
    public var tile: String
    public var file: String?
    public var map: String?

    public init(layer: String, tile: PaintTileIndex, file: String?, map: PaintMap = .color) {
        self.layer = layer
        self.tile = tile.key
        self.file = file
        self.map = map == .color ? nil : map.rawValue
    }

    /// The map it changes: colour when it names none, nil when it names one this app doesn't know.
    public var paintMap: PaintMap? {
        guard let map else { return .color }
        return PaintMap(rawValue: map)
    }
}

public extension SceneObject {
    /// Whether this kind of object can take paint: shapes, solid drawings, modelled meshes and placed models (not
    /// characters, ink, text or cards).
    var isPaintable: Bool {
        switch kind {
        case .primitive, .mesh: true
        case let .drawing(recipe): recipe.style != .ink
        case .asset: true
        default: false
        }
    }
}
