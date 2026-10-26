import Foundation

/// Meshes, skins, materials and pictures in three.js's scene format.
extension ThreeJSONBuilder {
    /// A node with one piece becomes the mesh itself; with several, a group of meshes named as `GLTFLoader` names them.
    mutating func meshObjects(_ mesh: Int, node: [String: Any], index: Int, into object: inout [String: Any]) -> [[String: Any]] {
        let meshes = file.array("meshes")
        guard mesh < meshes.count else { return [] }
        let base = meshes[mesh]["name"] as? String ?? "mesh_\(mesh)"
        let primitives = (meshes[mesh]["primitives"] as? [[String: Any]] ?? []).filter { ($0["mode"] as? Int ?? 4) == 4 }
        let skin = node["skin"] as? Int
        let names = (meshes[mesh]["extras"] as? [String: Any])?["targetNames"] as? [String] ?? []
        let weights = GLTFReader.numbers(meshes[mesh]["weights"])
        let pieces = primitives.enumerated().compactMap { number, primitive in
            piece(primitive, uuid: "maquette-geometry-\(mesh)-\(number)", weights: weights, targetNames: names)
        }
        if pieces.count == 1, let piece = pieces.first {
            dress(&object, piece: piece, skin: skin, node: index)
            return []
        }
        object["type"] = "Group"
        return pieces.enumerated().map { number, piece in
            var child: [String: Any] = ["uuid": "\(Self.nodeUUID(index))-\(number)", "name": number == 0 ? base : "\(base)_\(number)",
                                        "matrix": ThreeMatrix.identity, "layers": 1, "up": [0, 1, 0]]
            dress(&child, piece: piece, skin: skin, node: index)
            return child
        }
    }

    struct Piece {
        var geometry: String
        var material: String
        var materialIndex: Int?
        var morphWeights: [Double]?
    }

    mutating func dress(_ object: inout [String: Any], piece: Piece, skin: Int?, node: Int) {
        object["type"] = skin == nil ? "Mesh" : "SkinnedMesh"
        object["geometry"] = piece.geometry
        object["material"] = piece.material
        if let weights = piece.morphWeights { object["morphTargetInfluences"] = weights }
        if let material = piece.materialIndex, let name = object["name"] as? String { meshNamesOfMaterial[material, default: []].append(name) }
        guard let skin else { return }
        object["bindMode"] = "attached"
        object["bindMatrix"] = worldMatrix[node] ?? ThreeMatrix.identity
        object["skeleton"] = skeleton(skin)
    }

    mutating func skeleton(_ index: Int) -> String {
        let uuid = "maquette-skin-\(index)"
        guard !skeletons.contains(where: { $0["uuid"] as? String == uuid }), index < file.array("skins").count else { return uuid }
        let skin = file.array("skins")[index]
        let joints = skin["joints"] as? [Int] ?? []
        let inverses = (skin["inverseBindMatrices"] as? Int).flatMap { try? GLTFReader.accessor(file, $0).values } ?? []
        let boneInverses = joints.indices.map { number in
            inverses.count >= (number + 1) * 16 ? Array(inverses[number * 16 ..< (number + 1) * 16]) : ThreeMatrix.identity
        }
        skeletons.append(["uuid": uuid, "bones": joints.map(Self.nodeUUID), "boneInverses": boneInverses])
        return uuid
    }

    // MARK: Geometry

    static let attributeNames: [(gltf: String, three: String, array: String)] = [
        ("POSITION", "position", "Float32Array"), ("NORMAL", "normal", "Float32Array"), ("TEXCOORD_0", "uv", "Float32Array"),
        ("TEXCOORD_1", "uv1", "Float32Array"), ("COLOR_0", "color", "Float32Array"), ("TANGENT", "tangent", "Float32Array"),
        ("JOINTS_0", "skinIndex", "Uint16Array"), ("WEIGHTS_0", "skinWeight", "Float32Array")
    ]

    mutating func piece(_ primitive: [String: Any], uuid: String, weights: [Double]?, targetNames: [String]) -> Piece? {
        guard let attributes = primitive["attributes"] as? [String: Any], attributes["POSITION"] != nil else { return nil }
        var data: [String: Any] = [:]
        var written: [String: Any] = [:]
        for name in Self.attributeNames {
            guard let index = attributes[name.gltf] as? Int, let accessor = try? GLTFReader.accessor(file, index) else { continue }
            written[name.three] = ["itemSize": accessor.components, "type": name.array, "array": Self.rounded(accessor.values), "normalized": false]
        }
        data["attributes"] = written
        if let indices = primitive["indices"] as? Int, let accessor = try? GLTFReader.accessor(file, indices) {
            data["index"] = ["type": "Uint32Array", "array": accessor.values.map { Int($0) }]
        }
        let targets = primitive["targets"] as? [[String: Any]] ?? []
        if !targets.isEmpty {
            data["morphAttributes"] = morphAttributes(targets, names: targetNames)
            data["morphTargetsRelative"] = true
        }
        geometries.append(["uuid": uuid, "type": "BufferGeometry", "data": data])
        let materialIndex = primitive["material"] as? Int
        let material = material(materialIndex, vertexColors: attributes["COLOR_0"] != nil)
        return Piece(geometry: uuid, material: material, materialIndex: materialIndex, morphWeights: targets.isEmpty ? nil : weights ?? targets.map { _ in 0 })
    }

    func morphAttributes(_ targets: [[String: Any]], names: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (gltf, three) in [("POSITION", "position"), ("NORMAL", "normal")] {
            let list = targets.enumerated().compactMap { number, target -> [String: Any]? in
                guard let index = target[gltf] as? Int, let accessor = try? GLTFReader.accessor(file, index) else { return nil }
                var attribute: [String: Any] = ["itemSize": accessor.components, "type": "Float32Array", "array": Self.rounded(accessor.values),
                                                "normalized": false]
                if number < names.count { attribute["name"] = names[number] }
                return attribute
            }
            if list.count == targets.count { result[three] = list }
        }
        return result
    }

    /// Single precision written as single precision (no `0.30000001192092896`).
    static func rounded(_ values: [Double]) -> [Double] {
        values.map { ($0 * 1e6).rounded() / 1e6 }
    }

    // MARK: Materials

    mutating func material(_ index: Int?, vertexColors: Bool) -> String {
        let key = "\(index ?? -1)-\(vertexColors)"
        if let uuid = materialUUID[key] { return uuid }
        let uuid = "maquette-material-\(index ?? -1)\(vertexColors ? "-vc" : "")"
        materialUUID[key] = uuid
        let written = file.array("materials")
        let source = index.flatMap { written.indices.contains($0) ? written[$0] : nil } ?? [:]
        let json = materialJSON(source, uuid: uuid, index: index, vertexColors: vertexColors)
        materials.append(json)
        return uuid
    }

    mutating func materialJSON(_ source: [String: Any], uuid: String, index: Int?, vertexColors: Bool) -> [String: Any] {
        let pbr = source["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let extensions = source["extensions"] as? [String: Any] ?? [:]
        let base = GLTFReader.numbers(pbr["baseColorFactor"]) ?? [1, 1, 1, 1]
        let coat = extensions["KHR_materials_clearcoat"] as? [String: Any]
        var json: [String: Any] = [
            "uuid": uuid, "type": coat == nil ? "MeshStandardMaterial" : "MeshPhysicalMaterial",
            "name": source["name"] as? String ?? "", "color": ThreeMatrix.hex(base), "opacity": base.count > 3 ? base[3] : 1,
            "roughness": pbr["roughnessFactor"] as? Double ?? 1, "metalness": pbr["metallicFactor"] as? Double ?? 1,
            "emissive": ThreeMatrix.hex(GLTFReader.numbers(source["emissiveFactor"]) ?? [0, 0, 0]),
            "emissiveIntensity": (extensions["KHR_materials_emissive_strength"] as? [String: Any])?["emissiveStrength"] as? Double ?? 1,
            "vertexColors": vertexColors, "side": source["doubleSided"] as? Bool == true ? 2 : 0, "depthTest": true, "depthWrite": true
        ]
        if let coat {
            json["clearcoat"] = coat["clearcoatFactor"] as? Double ?? 0
            json["clearcoatRoughness"] = coat["clearcoatRoughnessFactor"] as? Double ?? 0
        }
        switch source["alphaMode"] as? String {
        case "BLEND":
            json["transparent"] = true
            json["depthWrite"] = false
        case "MASK":
            json["alphaTest"] = source["alphaCutoff"] as? Double ?? 0.5
        default:
            if let index, fadingMaterials.contains(index) { json["transparent"] = true }
        }
        let maps: [(key: String, texture: Any?, colour: Bool)] = [
            ("map", pbr["baseColorTexture"], true), ("roughnessMap", pbr["metallicRoughnessTexture"], false),
            ("metalnessMap", pbr["metallicRoughnessTexture"], false), ("normalMap", source["normalTexture"], false),
            ("emissiveMap", source["emissiveTexture"], true), ("aoMap", source["occlusionTexture"], false)
        ]
        for map in maps {
            guard let reference = map.texture as? [String: Any], let texture = reference["index"] as? Int,
                  let uuid = self.texture(texture, colour: map.colour) else { continue }
            json[map.key] = uuid
        }
        return json
    }

    /// A glTF texture as three.js's texture and image (a data URL), once per colour space.
    mutating func texture(_ index: Int, colour: Bool) -> String? {
        let key = "\(index)-\(colour)"
        if let uuid = textureUUID[key] { return uuid }
        let gltfTextures = file.array("textures"), gltfImages = file.array("images"), views = file.array("bufferViews")
        guard index < gltfTextures.count, let source = gltfTextures[index]["source"] as? Int, source < gltfImages.count,
              let viewIndex = gltfImages[source]["bufferView"] as? Int, viewIndex < views.count, let buffer = file.buffers.first else { return nil }
        let view = views[viewIndex]
        let start = view["byteOffset"] as? Int ?? 0, length = view["byteLength"] as? Int ?? 0
        guard start + length <= buffer.count else { return nil }
        let bytes = buffer.subdata(in: buffer.startIndex + start ..< buffer.startIndex + start + length)
        let image = "maquette-image-\(source)"
        if !images.contains(where: { $0["uuid"] as? String == image }) {
            let mime = gltfImages[source]["mimeType"] as? String ?? "image/png"
            images.append(["uuid": image, "url": "data:\(mime);base64,\(bytes.base64EncodedString())"])
        }
        let uuid = "maquette-texture-\(index)\(colour ? "-srgb" : "")"
        textureUUID[key] = uuid
        textures.append([
            "uuid": uuid, "name": "", "image": image, "mapping": 300, "channel": 0, "repeat": [1, 1], "offset": [0, 0], "center": [0, 0],
            "rotation": 0, "wrap": [1000, 1000], "format": 1023, "internalFormat": NSNull(), "type": 1009,
            "colorSpace": colour ? "srgb" : "", "minFilter": 1008, "magFilter": 1006, "anisotropy": 1, "flipY": false,
            "generateMipmaps": true, "premultiplyAlpha": false, "unpackAlignment": 4
        ])
        return uuid
    }
}
