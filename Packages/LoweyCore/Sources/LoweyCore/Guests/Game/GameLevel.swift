import Foundation

/// A level for a game engine (G1, Game: Dev's level to Godot), as one glTF each engine reads its own way:
/// - **Godot** makes a static body with the shape as its collision from a node named `…-col`, and makes its own
///   lower-detail copies on import.
/// - **Unity** groups `…_LOD0`, `…_LOD1`, `…_LOD2` under one parent into a LOD group; it has no naming for collision,
///   so each piece gets a convex `…_collider` beside it to put a Mesh Collider on.
/// - **Unreal** takes `UCX_…_00` convex shapes as the collision of the piece they're named after.
/// One texture for everything (an atlas) is a choice: every piece's painted colour, or its flat colour as a small
/// swatch, packed into one picture, so the whole level is one material.
public enum GameLevel {
    public struct Options: Sendable, Hashable {
        public var engine: GameEngine
        public var collision: Bool
        public var lods: Bool
        public var atlas: Bool

        public init(engine: GameEngine, collision: Bool = true, lods: Bool = true, atlas: Bool = false) {
            self.engine = engine
            self.collision = collision
            self.lods = lods
            self.atlas = atlas
        }
    }

    /// One node of the level: a mesh in the piece's own space, its place, its name, and which material it takes.
    struct Node {
        var name: String
        var transform: Transform
        var mesh: MeshData?
        var material: Int?
        var children: [Int] = []
    }

    /// The level's file from its pieces as placed (`ModelExport.meshes`).
    public static func glb(_ pieces: [ExportMesh], options: Options) -> Data {
        var writer = LevelWriter()
        var meshes = pieces.filter { !$0.mesh.isEmpty }
        var shared: Int?
        if options.atlas, let atlas = TextureAtlas.pack(meshes) {
            meshes = atlas.meshes
            shared = writer.addMaterial(name: "Level", color: .white, roughness: 0.85, metallic: 0, texture: atlas.png)
        }
        var names: [String: Int] = [:]
        for piece in meshes {
            let base = unique(piece.name.isEmpty ? "Piece" : piece.name, in: &names)
            let material = shared ?? writer.addMaterial(name: base, color: piece.color, roughness: piece.roughness, metallic: piece.metallic,
                                                        texture: piece.texture)
            let lodMeshes = options.lods && options.engine == .unity ? lods(piece.mesh) : []
            if lodMeshes.isEmpty {
                let name = options.collision && options.engine == .godot ? "\(base)-col" : base
                writer.root(Node(name: name, transform: piece.transform, mesh: piece.mesh, material: material))
            } else {
                var group = Node(name: base, transform: piece.transform)
                for (level, mesh) in ([piece.mesh] + lodMeshes).enumerated() {
                    group.children.append(writer.add(Node(name: "\(base)_LOD\(level)", transform: .identity, mesh: mesh, material: material)))
                }
                writer.root(group)
            }
            if options.collision, options.engine != .godot, let hull = hull(piece.mesh) {
                let name = options.engine == .unreal ? "UCX_\(base)_00" : "\(base)_collider"
                writer.root(Node(name: name, transform: piece.transform, mesh: hull, material: nil))
            }
        }
        return writer.finish()
    }

    static func unique(_ name: String, in names: inout [String: Int]) -> String {
        let clean = String(name.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : "_" }).replacingOccurrences(of: " ", with: "_")
        let count = names[clean, default: 0]
        names[clean] = count + 1
        return count == 0 ? clean : "\(clean)_\(count + 1)"
    }

    /// Half and a quarter of the triangles (UVs carried from the nearest corner), when the piece is worth lightening.
    static func lods(_ mesh: MeshData) -> [MeshData] {
        guard mesh.triangleCount >= 64 else { return [] }
        let uvs = mesh.uvs.count == mesh.positions.count ? mesh.uvs.map { SIMD4<Float>($0.x, $0.y, 0, 0) } : []
        return [2, 4].map { divisor in
            let (lighter, carried) = MeshSimplify.simplified(mesh, colors: uvs, target: mesh.triangleCount / divisor)
            var result = lighter
            if carried.count == lighter.positions.count { result.uvs = carried.map { SIMD2<Float>($0.x, $0.y) } }
            return result
        }
    }

    /// The piece's convex hull in its own space.
    static func hull(_ mesh: MeshData) -> MeshData? {
        let points = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let triangles = QuickHull3D.hull(points)
        guard !triangles.isEmpty else { return nil }
        var result = MeshData()
        for (a, b, c) in triangles {
            let start = UInt32(result.positions.count)
            let normal = (b - a).cross(c - a).normalized.float3
            result.positions += [a.float3, b.float3, c.float3]
            result.normals += [normal, normal, normal]
            result.uvs += [.zero, .zero, .zero]
            result.indices += [start, start + 1, start + 2]
        }
        return result
    }
}

/// Every piece's colour in one picture (G1, Game): painted pieces bring their texture (at most 1024 pixels a side),
/// plain ones a small swatch of their colour; all are packed in rows into one square picture with a gap round each,
/// and each piece's UVs moved into its place.
public enum TextureAtlas {
    public struct Packed: Sendable {
        public var meshes: [ExportMesh]
        public var png: Data
        public var size: Int
    }

    public static func pack(_ meshes: [ExportMesh], limit: Int = 4096) -> Packed? {
        guard !meshes.isEmpty else { return nil }
        let pictures: [RGBAImage] = meshes.map { mesh in
            if let data = mesh.texture, let image = try? PNGCodec.decode(data) { return shrunk(image, to: 1024) }
            return RGBAImage(width: 8, height: 8, color: RGBA(mesh.color.r, mesh.color.g, mesh.color.b, 1))
        }
        let gap = 4
        var size = 64
        var places: [(x: Int, y: Int)] = []
        while size <= limit {
            if let fitted = shelves(pictures, size: size, gap: gap) {
                places = fitted
                break
            }
            size *= 2
        }
        guard places.count == pictures.count else { return nil }
        var atlas = RGBAImage(width: size, height: size, color: RGBA(1, 1, 1, 1))
        var result: [ExportMesh] = []
        for (index, mesh) in meshes.enumerated() {
            let picture = pictures[index], place = places[index]
            atlas.place(picture, x: place.x, y: place.y)
            var moved = mesh
            let scale = SIMD2<Float>(Float(picture.width) / Float(size), Float(picture.height) / Float(size))
            let offset = SIMD2<Float>(Float(place.x) / Float(size), Float(place.y) / Float(size))
            if mesh.texture != nil, mesh.mesh.uvs.count == mesh.mesh.positions.count {
                moved.mesh.uvs = mesh.mesh.uvs.map { offset + SIMD2<Float>(min(max($0.x, 0), 1), min(max($0.y, 0), 1)) * scale }
            } else {
                moved.mesh.uvs = Array(repeating: offset + scale * 0.5, count: mesh.mesh.positions.count)
            }
            moved.color = .white
            moved.texture = nil
            result.append(moved)
        }
        return Packed(meshes: result, png: PNGCodec.encode(atlas), size: size)
    }

    /// Rows, tallest pictures first; nil when they don't fit `size`.
    static func shelves(_ pictures: [RGBAImage], size: Int, gap: Int) -> [(x: Int, y: Int)]? {
        let order = pictures.indices.sorted { pictures[$0].height > pictures[$1].height }
        var places = [(x: Int, y: Int)](repeating: (0, 0), count: pictures.count)
        var x = gap, y = gap, row = 0
        for index in order {
            let picture = pictures[index]
            if x + picture.width + gap > size {
                x = gap
                y += row + gap
                row = 0
            }
            guard x + picture.width + gap <= size, y + picture.height + gap <= size else { return nil }
            places[index] = (x, y)
            x += picture.width + gap
            row = max(row, picture.height)
        }
        return places
    }

    /// A picture no bigger than `side` pixels a side (every other pixel, as often as needed).
    static func shrunk(_ image: RGBAImage, to side: Int) -> RGBAImage {
        var result = image
        while result.width > side || result.height > side {
            let width = max(result.width / 2, 1), height = max(result.height / 2, 1)
            var smaller = RGBAImage(width: width, height: height, color: .white)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    smaller.setPixel(x, y, result.pixel(min(x * 2, result.width - 1), min(y * 2, result.height - 1)))
                }
            }
            result = smaller
        }
        return result
    }
}

/// A small glTF binary writer for levels: nodes with children, meshes with a material each (or none, for collision
/// shapes), materials with an optional texture.
struct LevelWriter {
    var binary = Data()
    var bufferViews: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var meshes: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var images: [[String: Any]] = []
    var textures: [[String: Any]] = []
    var nodes: [[String: Any]] = []
    var roots: [Int] = []

    mutating func view(_ data: Data, target: Int?) -> Int {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
        var entry: [String: Any] = ["buffer": 0, "byteOffset": binary.count, "byteLength": data.count]
        if let target { entry["target"] = target }
        bufferViews.append(entry)
        binary.append(data)
        return bufferViews.count - 1
    }

    mutating func accessor(_ floats: [Float], type: String, count: Int, bounds: Bool = false) -> Int {
        var data = Data(capacity: floats.count * 4)
        for value in floats {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        var entry: [String: Any] = ["bufferView": view(data, target: 34962), "componentType": 5126, "count": count, "type": type]
        if bounds, count > 0 {
            let xs = stride(from: 0, to: floats.count, by: 3).map { floats[$0] }, ys = stride(from: 1, to: floats.count, by: 3).map { floats[$0] }
            let zs = stride(from: 2, to: floats.count, by: 3).map { floats[$0] }
            entry["min"] = [xs.min() ?? 0, ys.min() ?? 0, zs.min() ?? 0]
            entry["max"] = [xs.max() ?? 0, ys.max() ?? 0, zs.max() ?? 0]
        }
        accessors.append(entry)
        return accessors.count - 1
    }

    mutating func addMaterial(name: String, color: RGBA, roughness: Double, metallic: Double, texture: Data?) -> Int {
        let linear = SceneExport.linear
        var pbr: [String: Any] = ["baseColorFactor": [linear(color.r), linear(color.g), linear(color.b), color.a],
                                  "metallicFactor": metallic, "roughnessFactor": roughness]
        if let texture {
            images.append(["bufferView": view(texture, target: nil), "mimeType": "image/png"])
            textures.append(["source": images.count - 1])
            pbr["baseColorTexture"] = ["index": textures.count - 1]
        }
        materials.append(["name": name, "pbrMetallicRoughness": pbr])
        return materials.count - 1
    }

    mutating func add(_ node: GameLevel.Node) -> Int {
        let t = node.transform
        var entry: [String: Any] = [
            "name": node.name, "translation": [t.position.x, t.position.y, t.position.z],
            "rotation": [t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w], "scale": [t.scale.x, t.scale.y, t.scale.z]
        ]
        if let mesh = node.mesh, !mesh.isEmpty {
            var attributes = ["POSITION": accessor(mesh.positions.flatMap { [$0.x, $0.y, $0.z] }, type: "VEC3", count: mesh.positions.count,
                                                   bounds: true)]
            if mesh.normals.count == mesh.positions.count {
                attributes["NORMAL"] = accessor(mesh.normals.flatMap { n -> [Float] in
                    let l = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                    return l > 0 ? [n.x / l, n.y / l, n.z / l] : [0, 1, 0]
                }, type: "VEC3", count: mesh.normals.count)
            }
            if mesh.uvs.count == mesh.positions.count {
                attributes["TEXCOORD_0"] = accessor(mesh.uvs.flatMap { [$0.x, $0.y] }, type: "VEC2", count: mesh.uvs.count)
            }
            var indexData = Data(capacity: mesh.indices.count * 4)
            for value in mesh.indices {
                withUnsafeBytes(of: value.littleEndian) { indexData.append(contentsOf: $0) }
            }
            accessors.append(["bufferView": view(indexData, target: 34963), "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])
            var primitive: [String: Any] = ["attributes": attributes, "indices": accessors.count - 1]
            if let material = node.material { primitive["material"] = material }
            meshes.append(["name": node.name, "primitives": [primitive]])
            entry["mesh"] = meshes.count - 1
        }
        if !node.children.isEmpty { entry["children"] = node.children }
        nodes.append(entry)
        return nodes.count - 1
    }

    mutating func root(_ node: GameLevel.Node) {
        roots.append(add(node))
    }

    mutating func finish() -> Data {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Maquette"], "scene": 0, "scenes": [["nodes": roots]], "nodes": nodes,
            "meshes": meshes, "accessors": accessors, "bufferViews": bufferViews, "buffers": [["byteLength": binary.count]]
        ]
        if !materials.isEmpty { json["materials"] = materials }
        if !images.isEmpty {
            json["images"] = images
            json["textures"] = textures
        }
        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 {
            jsonData.append(0x20)
        }
        var result = Data()
        func u32(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { result.append(contentsOf: $0) }
        }
        result.append(Data("glTF".utf8))
        u32(2)
        u32(12 + 8 + jsonData.count + 8 + binary.count)
        u32(jsonData.count)
        result.append(Data("JSON".utf8))
        result.append(jsonData)
        u32(binary.count)
        result.append(contentsOf: [0x42, 0x49, 0x4E, 0x00])
        result.append(binary)
        return result
    }
}
