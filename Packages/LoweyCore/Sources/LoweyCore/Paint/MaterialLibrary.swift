import Foundation
import HmmDocuments

/// The materials that come with the app (D-342): our own, procedural, in plain words. Wood, metals, plastic, fabric,
/// stone, concrete, brick, glass and the rest; the person's own sit beside them in the library.
public enum BuiltInMaterials {
    public static let all: [PaintMaterial] = woods + metals + everyday + mineral

    static let woods: [PaintMaterial] = [
        PaintMaterial(id: "oak", name: "Oak", color: .hex("#B08350"), secondColor: .hex("#7A5430"), roughness: 0.62, pattern: .wood,
                      scale: 0.25, variation: 0.8, bumps: 0.25),
        PaintMaterial(id: "pine", name: "Pine", color: .hex("#D9B27A"), secondColor: .hex("#B07E45"), roughness: 0.66, pattern: .wood,
                      scale: 0.3, variation: 0.75, bumps: 0.2),
        PaintMaterial(id: "walnut", name: "Walnut", color: .hex("#6B4428"), secondColor: .hex("#3E2414"), roughness: 0.5, pattern: .wood,
                      scale: 0.22, variation: 0.8, bumps: 0.2),
        PaintMaterial(id: "floorboards", name: "Floorboards", color: .hex("#A97A4A"), secondColor: .hex("#5C3B20"), roughness: 0.55,
                      pattern: .planks, scale: 0.15, variation: 0.7, bumps: 0.4)
    ]

    static let metals: [PaintMaterial] = [
        PaintMaterial(id: "steel", name: "Brushed steel", color: .hex("#A8ABB0"), secondColor: .hex("#7F8389"), roughness: 0.35, metal: 1,
                      pattern: .brushed, scale: 0.2, variation: 0.5, bumps: 0.08),
        PaintMaterial(id: "aluminium", name: "Aluminium", color: .hex("#C9CCD1"), roughness: 0.3, metal: 1, pattern: .noise, scale: 0.4,
                      variation: 0.1, bumps: 0.02),
        PaintMaterial(id: "gold", name: "Gold", color: .hex("#E8B64C"), secondColor: .hex("#C9952F"), roughness: 0.22, metal: 1,
                      pattern: .noise, scale: 0.3, variation: 0.15, bumps: 0.02),
        PaintMaterial(id: "copper", name: "Copper", color: .hex("#C9734A"), secondColor: .hex("#9C5133"), roughness: 0.28, metal: 1,
                      pattern: .noise, scale: 0.3, variation: 0.2, bumps: 0.03),
        PaintMaterial(id: "iron", name: "Cast iron", color: .hex("#4A4C50"), secondColor: .hex("#2E3033"), roughness: 0.7, metal: 0.9,
                      pattern: .concrete, scale: 0.3, variation: 0.4, bumps: 0.25),
        PaintMaterial(id: "rust", name: "Rusty metal", color: .hex("#5A5550"), secondColor: .hex("#8E4A22"), roughness: 0.55, metal: 0.9,
                      pattern: .rust, scale: 0.35, variation: 0.95, bumps: 0.35)
    ]

    static let everyday: [PaintMaterial] = [
        PaintMaterial(id: "plastic", name: "Glossy plastic", color: .hex("#E04F3F"), roughness: 0.25, pattern: .none, bumps: 0),
        PaintMaterial(id: "rubber", name: "Rubber", color: .hex("#2B2B2D"), secondColor: .hex("#232325"), roughness: 0.92, pattern: .noise,
                      scale: 0.05, variation: 0.3, bumps: 0.1),
        PaintMaterial(id: "fabric", name: "Cotton", color: .hex("#D8D2C4"), secondColor: .hex("#B8B0A0"), roughness: 0.95, pattern: .weave,
                      scale: 0.06, variation: 0.6, bumps: 0.35),
        PaintMaterial(id: "denim", name: "Denim", color: .hex("#3F5A80"), secondColor: .hex("#8A9BB3"), roughness: 0.9, pattern: .weave,
                      scale: 0.04, variation: 0.55, bumps: 0.4),
        PaintMaterial(id: "leather", name: "Leather", color: .hex("#6E3F24"), secondColor: .hex("#4A2915"), roughness: 0.6, pattern: .leather,
                      scale: 0.1, variation: 0.5, bumps: 0.4),
        PaintMaterial(id: "glass", name: "Glass", color: .hex("#BFD8DE"), secondColor: .hex("#A9C6CD"), roughness: 0.05, pattern: .none,
                      bumps: 0),
        PaintMaterial(id: "ceramic", name: "Ceramic", color: .hex("#F2EEE6"), roughness: 0.15, pattern: .noise, scale: 0.5, variation: 0.05,
                      bumps: 0.02),
        PaintMaterial(id: "neon", name: "Neon", color: .hex("#FF4FA3"), roughness: 0.4, glow: .hex("#FF4FA3"), pattern: .none, bumps: 0)
    ]

    static let mineral: [PaintMaterial] = [
        PaintMaterial(id: "stone", name: "Stone", color: .hex("#8C8A84"), secondColor: .hex("#55534F"), roughness: 0.85, pattern: .stone,
                      scale: 0.5, variation: 0.6, bumps: 0.5),
        PaintMaterial(id: "marble", name: "Marble", color: .hex("#EDEBE6"), secondColor: .hex("#7D7A76"), roughness: 0.2, pattern: .marble,
                      scale: 0.6, variation: 0.7, bumps: 0.03),
        PaintMaterial(id: "concrete", name: "Concrete", color: .hex("#A3A19C"), secondColor: .hex("#7C7A75"), roughness: 0.9,
                      pattern: .concrete, scale: 0.4, variation: 0.5, bumps: 0.3),
        PaintMaterial(id: "brick", name: "Brick", color: .hex("#9E4A35"), secondColor: .hex("#CFC8BC"), roughness: 0.85, pattern: .bricks,
                      scale: 0.22, variation: 1, bumps: 0.6),
        PaintMaterial(id: "tiles", name: "Tiles", color: .hex("#E8E4DC"), secondColor: .hex("#9C978E"), roughness: 0.2, pattern: .tiles,
                      scale: 0.15, variation: 1, bumps: 0.45),
        PaintMaterial(id: "sand", name: "Sand", color: .hex("#D8BF8E"), secondColor: .hex("#B89A66"), roughness: 0.95, pattern: .sand,
                      scale: 0.5, variation: 0.6, bumps: 0.3)
    ]

    public static func material(_ id: String) -> PaintMaterial? {
        all.first { $0.id == id }
    }
}

/// Everyone's materials on this device: the built-ins (with any edits) and made or imported ones, newest first
/// (D-343). A project keeps its own copy of each material a fill uses, so edits here never change a project.
public struct MaterialLibrary: Codable, Hashable, Sendable {
    /// Made, imported and edited materials.
    public var materials: [String: PaintMaterial]
    /// The person's own, in the order the library shows them (newest first).
    public var order: [String]

    public init(materials: [String: PaintMaterial] = [:], order: [String] = []) {
        self.materials = materials
        self.order = order
    }

    public static let standard = MaterialLibrary()

    public func material(_ id: String) -> PaintMaterial? {
        materials[id] ?? BuiltInMaterials.material(id)
    }

    /// The person's own first, then the built-ins (edited ones as edited).
    public var all: [PaintMaterial] {
        order.compactMap { materials[$0] } + BuiltInMaterials.all.map { materials[$0.id] ?? $0 }
    }

    public var own: [PaintMaterial] {
        order.compactMap { materials[$0] }
    }

    public func isBuiltIn(_ id: String) -> Bool { BuiltInMaterials.material(id) != nil }

    public mutating func update(_ material: PaintMaterial) {
        materials[material.id] = material
        if !isBuiltIn(material.id), !order.contains(material.id) { order.insert(material.id, at: 0) }
    }

    /// A copy at the top of the person's own, named "… copy".
    @discardableResult
    public mutating func duplicate(_ id: String, as newID: String) -> PaintMaterial? {
        guard var copy = material(id) else { return nil }
        copy.id = newID
        copy.name = BrushLibrary.copyName(copy.name, existing: Set(all.map(\.name)))
        materials[newID] = copy
        order.insert(newID, at: 0)
        return copy
    }

    /// A built-in goes back to how it came; one of the person's own is deleted.
    public mutating func delete(_ id: String) {
        materials[id] = nil
        order.removeAll { $0 == id }
    }

    public mutating func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var material = material(id), !trimmed.isEmpty else { return }
        material.name = trimmed
        update(material)
    }

    /// Every picture file the library's materials name.
    public var files: Set<String> {
        Set(materials.values.flatMap { $0.pictures?.files ?? [] })
    }
}

/// The material library on disk: `materials.json` beside `materials/`, imported pictures by content hash
/// (`materials/<hash>.png`, the same key under a project's `assets/`, so a material moves by copying its files).
public struct MaterialLibraryStore: Sendable {
    public let root: URL
    public static let file = "materials.json"
    public static let imagesFolder = "materials"

    public init(root: URL) {
        self.root = root
    }

    public var fileURL: URL { root.appendingPathComponent(Self.file) }

    public func imageURL(_ key: String) -> URL { root.appendingPathComponent(key) }

    public func load() -> MaterialLibrary {
        var library: MaterialLibrary?
        _ = try? SafeFileWriter.read(fileURL) { data in
            library = try SchemaCoder.shared.decode(MaterialLibrary.self, kind: .materials, from: data)
        }
        return library ?? .standard
    }

    public func save(_ library: MaterialLibrary) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SafeFileWriter.write(SchemaCoder.shared.encode(library, kind: .materials), to: fileURL)
    }

    /// The key a picture is kept under (its content).
    public static func imageKey(for data: Data) -> String {
        "\(imagesFolder)/\(BrushKey.hex(BrushKey.fnv(data))).png"
    }

    /// Stores a picture under its content key (once).
    @discardableResult
    public func store(image data: Data) throws -> String {
        let key = Self.imageKey(for: data)
        let url = imageURL(key)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return key
    }
}
