import Foundation

// MARK: - USDZ

public extension SceneExport {
    /// USD text for the meshes (UsdPreviewSurface materials).
    static func usda(_ meshes: [ExportMesh]) -> String {
        var text = """
        #usda 1.0
        (
            defaultPrim = "Root"
            metersPerUnit = 1
            upAxis = "Y"
            doc = "Exported from Maquette"
        )

        def Xform "Root"
        {
            def Scope "Materials"
            {

        """
        for (index, item) in meshes.enumerated() {
            text += USDText.material(item, index: index)
        }
        text += "    }\n\n"
        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            text += USDText.mesh(item, index: index)
        }
        text += "}\n"
        return text
    }

    /// A USDZ package: an uncompressed zip whose files start on 64-byte boundaries (the scene, then painted textures).
    static func usdz(_ meshes: [ExportMesh]) -> Data {
        var files = [("scene.usda", Data(usda(meshes).utf8))]
        for (index, item) in meshes.enumerated() {
            if let texture = item.texture { files.append((USDText.textureFile(index), texture)) }
            for (map, data) in USDText.maps(item) {
                files.append((USDText.mapFile(index, map), data))
            }
        }
        return ZipWriter.storedArchive(files, alignment: 64)
    }
}

/// The pieces of a .usda file.
private enum USDText {
    static func f(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(rounded)
    }

    static func ff(_ value: Float) -> String { f(Double(value)) }

    static func identifier(_ name: String, _ index: Int) -> String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" }).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = cleaned.isEmpty || cleaned.first?.isNumber == true ? "Object_\(cleaned)" : cleaned
        return "\(base)_\(index)"
    }

    static func textureFile(_ index: Int) -> String {
        "textures/paint_\(index).png"
    }

    static func mapFile(_ index: Int, _ map: String) -> String {
        "textures/paint_\(index)_\(map).png"
    }

    /// The painted maps an item carries, by the name their reader shader takes.
    static func maps(_ item: ExportMesh) -> [(String, Data)] {
        [("roughness", item.maps.roughness), ("metal", item.maps.metal), ("emissive", item.maps.emissive), ("normal", item.maps.normal)]
            .compactMap { name, data in data.map { (name, $0) } }
    }

    static func material(_ item: ExportMesh, index: Int) -> String {
        let linear = SceneExport.linear
        let emissive = item.emissive.map { e in
            let s = min(item.emissiveStrength, 1)
            return "(\(f(linear(e.r) * s)), \(f(linear(e.g) * s)), \(f(linear(e.b) * s)))"
        } ?? "(0.0, 0.0, 0.0)"
        return """
                def Material "M\(index)"
                {
                    token outputs:surface.connect = </Root/Materials/M\(index)/Surface.outputs:surface>

                    def Shader "Surface"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        \(diffuse(item, index: index))
                        \(input("color3f", "emissiveColor", map: item.maps.emissive == nil ? nil : "emissive", output: "rgb", constant: emissive, index: index))
                        \(input("float", "roughness", map: item.maps.roughness == nil ? nil : "roughness", output: "r", constant: f(item.roughness), index: index))
                        \(input("float", "metallic", map: item.maps.metal == nil ? nil : "metal", output: "r", constant: f(item.metallic), index: index))
                        \(item.maps.normal == nil ? "" : "normal3f inputs:normal.connect = </Root/Materials/M\(index)/normal.outputs:rgb>")
                        float inputs:opacity = \(f(item.color.a))
                        token outputs:surface
                    }
        \(item.texture == nil ? "" : textureShaders(index))\(maps(item).map { mapShader(index, $0.0) }.joined())
                }

        """
    }

    /// The diffuse colour: a constant, or the painted texture's colour.
    static func diffuse(_ item: ExportMesh, index: Int) -> String {
        guard item.texture != nil else {
            let linear = SceneExport.linear
            return "color3f inputs:diffuseColor = (\(f(linear(item.color.r))), \(f(linear(item.color.g))), \(f(linear(item.color.b))))"
        }
        return "color3f inputs:diffuseColor.connect = </Root/Materials/M\(index)/Paint.outputs:rgb>"
    }

    /// An input as a constant, or read from a painted map's texture.
    static func input(_ type: String, _ name: String, map: String?, output: String, constant: String, index: Int) -> String {
        guard let map else { return "\(type) inputs:\(name) = \(constant)" }
        return "\(type) inputs:\(name).connect = </Root/Materials/M\(index)/\(map).outputs:\(output)>"
    }

    /// The reader of one painted map (raw values; a normal map scaled from 0…1 to −1…1).
    static func mapShader(_ index: Int, _ map: String) -> String {
        let normal = map == "normal"
        let colour = map == "emissive"
        let outputs = normal || colour ? "float3 outputs:rgb" : "float outputs:r"
        let scale = normal ? "\n                        float4 inputs:scale = (2, 2, 2, 1)\n                        float4 inputs:bias = (-1, -1, -1, 0)" : ""
        return """

                    def Shader "\(map)"
                    {
                        uniform token info:id = "UsdUVTexture"
                        asset inputs:file = @\(mapFile(index, map))@
                        float2 inputs:st.connect = </Root/Materials/M\(index)/UV.outputs:result>
                        token inputs:wrapS = "repeat"
                        token inputs:wrapT = "repeat"
                        token inputs:sourceColorSpace = "\(colour ? "sRGB" : "raw")"\(scale)
                        \(outputs)
                    }
        """
    }

    /// The texture reader and the uv reader of a painted material.
    static func textureShaders(_ index: Int) -> String {
        """

                    def Shader "Paint"
                    {
                        uniform token info:id = "UsdUVTexture"
                        asset inputs:file = @\(textureFile(index))@
                        float2 inputs:st.connect = </Root/Materials/M\(index)/UV.outputs:result>
                        token inputs:wrapS = "repeat"
                        token inputs:wrapT = "repeat"
                        token inputs:sourceColorSpace = "sRGB"
                        float3 outputs:rgb
                    }

                    def Shader "UV"
                    {
                        uniform token info:id = "UsdPrimvarReader_float2"
                        token inputs:varname = "st"
                        float2 outputs:result
                    }
        """
    }

    static func mesh(_ item: ExportMesh, index: Int) -> String {
        let t = item.transform
        let mesh = item.mesh
        let counts = Array(repeating: "3", count: mesh.indices.count / 3).joined(separator: ", ")
        let indices = mesh.indices.map { String($0) }.joined(separator: ", ")
        let points = mesh.positions.map { "(\(ff($0.x)), \(ff($0.y)), \(ff($0.z)))" }.joined(separator: ", ")
        var extras = ""
        if mesh.normals.count == mesh.positions.count {
            let normals = mesh.normals.map { "(\(ff($0.x)), \(ff($0.y)), \(ff($0.z)))" }.joined(separator: ", ")
            extras += "            normal3f[] normals = [\(normals)] (\n                interpolation = \"vertex\"\n            )\n"
        }
        if mesh.uvs.count == mesh.positions.count {
            // USD's texture origin is the bottom left; glTF's (and the paint's) the top left.
            let flip = item.texture != nil
            let uvs = mesh.uvs.map { "(\(ff($0.x)), \(ff(flip ? 1 - $0.y : $0.y)))" }.joined(separator: ", ")
            extras += "            texCoord2f[] primvars:st = [\(uvs)] (\n                interpolation = \"vertex\"\n            )\n"
        }
        let head = """
            def Xform "\(identifier(item.name, index))"
            {
                double3 xformOp:translate = (\(f(t.position.x)), \(f(t.position.y)), \(f(t.position.z)))
                quatf xformOp:orient = (\(f(t.rotation.w)), \(f(t.rotation.x)), \(f(t.rotation.y)), \(f(t.rotation.z)))
                float3 xformOp:scale = (\(f(t.scale.x)), \(f(t.scale.y)), \(f(t.scale.z)))
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:orient", "xformOp:scale"]

                def Mesh "Mesh"
                {
                    int[] faceVertexCounts = [\(counts)]
                    int[] faceVertexIndices = [\(indices)]
                    point3f[] points = [\(points)]
                    uniform token orientation = "rightHanded"
                    uniform token subdivisionScheme = "none"
                    rel material:binding = </Root/Materials/M\(index)>

        """
        return head + extras + "        }\n    }\n\n"
    }
}
