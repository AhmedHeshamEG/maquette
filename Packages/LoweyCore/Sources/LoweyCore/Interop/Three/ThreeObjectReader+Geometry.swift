import Foundation

/// Shapes and surfaces from three.js's scene format.
extension ThreeReaderBuilder {
    /// A geometry as an editable mesh: buffer geometry as its triangles, three.js's own boxes exactly, spheres, cylinders,
    /// cones and planes at their sizes. Other kinds are named in a note.
    mutating func mesh(_ uuid: String?) -> EditableMesh? {
        guard let uuid, let geometry = geometries[uuid] else { return nil }
        let type = geometry["type"] as? String ?? ""
        let data: MeshData?
        switch type {
        case "BufferGeometry":
            data = buffer(geometry["data"] as? [String: Any] ?? [:])
        case "BoxGeometry":
            let size = Vec3(number(geometry, "width", 1), number(geometry, "height", 1), number(geometry, "depth", 1))
            triangles += 12
            return EditableMesh.box(min: size * -0.5, max: size * 0.5)
        case "SphereGeometry":
            let diameter = number(geometry, "radius", 1) * 2
            data = sized(.sphere, to: Vec3(diameter, diameter, diameter))
        case "CylinderGeometry":
            let diameter = (number(geometry, "radiusTop", 1) + number(geometry, "radiusBottom", 1))
            data = sized(.cylinder, to: Vec3(diameter, number(geometry, "height", 1), diameter))
        case "ConeGeometry":
            let diameter = number(geometry, "radius", 1) * 2
            data = sized(.cone, to: Vec3(diameter, number(geometry, "height", 1), diameter))
        case "PlaneGeometry":
            // three.js's plane stands in XY, facing +Z.
            let (w, h) = (Float(number(geometry, "width", 1) / 2), Float(number(geometry, "height", 1) / 2))
            data = MeshData(positions: [SIMD3(-w, -h, 0), SIMD3(w, -h, 0), SIMD3(w, h, 0), SIMD3(-w, h, 0)], indices: [0, 1, 2, 0, 2, 3])
        default:
            notes.insert("\(type): not read yet; those things came in as empty groups.")
            data = nil
        }
        guard let data, !data.indices.isEmpty else { return nil }
        triangles += data.indices.count / 3
        let mesh = MeshBuilder.mesh(from: data)
        return mesh.isEmpty ? nil : mesh
    }

    func number(_ geometry: [String: Any], _ key: String, _ fallback: Double) -> Double {
        geometry[key] as? Double ?? fallback
    }

    /// Maquette's own primitive stretched to a size (its bounds become the size, centred).
    func sized(_ shape: PrimitiveShape, to size: Vec3) -> MeshData? {
        var data = PrimitiveMesh.make(shape, shading: .smooth)
        guard let bounds = data.bounds else { return nil }
        let extent = bounds.max - bounds.min, centre = (bounds.max + bounds.min) * 0.5
        let scale = SIMD3<Float>(Float(size.x / max(extent.x, 1e-9)), Float(size.y / max(extent.y, 1e-9)), Float(size.z / max(extent.z, 1e-9)))
        let middle = SIMD3<Float>(Float(centre.x), Float(centre.y), Float(centre.z))
        data.positions = data.positions.map { ($0 - middle) * scale }
        return data
    }

    /// `BufferGeometry`'s positions and index (no index: every three corners a triangle), and its uvs when asked.
    func buffer(_ data: [String: Any], uvs: Bool = false) -> MeshData? {
        let attributes = data["attributes"] as? [String: Any] ?? [:]
        guard let position = attributes["position"] as? [String: Any], let values = GLTFReader.numbers(position["array"]) else { return nil }
        let size = position["itemSize"] as? Int ?? 3
        guard size >= 3 else { return nil }
        let count = values.count / size
        let positions = (0 ..< count).map { SIMD3<Float>(Float(values[$0 * size]), Float(values[$0 * size + 1]), Float(values[$0 * size + 2])) }
        let indices = GLTFReader.numbers((data["index"] as? [String: Any])?["array"]).map { $0.map { UInt32(max($0, 0)) } }
            ?? (0 ..< UInt32(count - count % 3)).map { $0 }
        var mesh = MeshData(positions: positions, indices: indices.filter { Int($0) < count })
        if uvs, let uv = attributes["uv"] as? [String: Any], let values = GLTFReader.numbers(uv["array"]), (uv["itemSize"] as? Int ?? 2) == 2,
           values.count >= count * 2 {
            mesh.uvs = (0 ..< count).map { SIMD2<Float>(Float(values[$0 * 2]), Float(values[$0 * 2 + 1])) }
        }
        return mesh
    }

    /// A three.js material as colour, roughness, metal, glow and see-through.
    mutating func apply(_ material: [String: Any], to object: inout SceneObject) {
        let type = material["type"] as? String ?? ""
        if type == "MeshToonMaterial" {
            suggestsToon = true
            notes.insert("Toon materials: a toon Look (Ink, Comic, Anime cel) suits this scene.")
        }
        if ["ShaderMaterial", "RawShaderMaterial"].contains(type) {
            notes.insert("Custom shaders: a file can't carry their code, so those surfaces came in plain (bring the project folder in to keep them).")
        }
        object[.color] = .color(.rgba(Self.colour(material["color"] as? Int ?? 0xFFFFFF)))
        if let roughness = material["roughness"] as? Double { object[.roughness] = .float(roughness) }
        if let metalness = material["metalness"] as? Double { object[.metallic] = .float(metalness) }
        if let emissive = material["emissive"] as? Int, emissive != 0 {
            object[.emissive] = .color(.rgba(Self.colour(emissive)))
            object[.emissiveIntensity] = .float(material["emissiveIntensity"] as? Double ?? 1)
        }
        if let opacity = material["opacity"] as? Double, opacity < 1, material["transparent"] as? Bool == true { object[.opacity] = .float(opacity) }
    }
}
