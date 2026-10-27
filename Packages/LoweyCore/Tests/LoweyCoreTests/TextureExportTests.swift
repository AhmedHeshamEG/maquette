import Foundation
@testable import LoweyCore
import XCTest

/// U7's acceptance: a painted, smudged, masked model leaves with every map (golden); the bridge's `paint` verb.
final class TextureExportTests: XCTestCase {
    /// A crate: a red colour layer smudged sideways, a brick fill masked to its left half, a strip of glow and a
    /// rough patch. Every file it needs, by name.
    private func crate(size: Int = 256) throws -> (Scene, Look, [String: Data]) {
        var cube = SceneObject(id: "crate", name: "Crate", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(1, 1, 1)))
        let source = try XCTUnwrap(PaintSource.mesh(of: cube))
        let prepared = try PaintOperations.prepare(mesh: source, keepOwnUVs: false, size: size)
        var paint = prepared.paint
        var files = prepared.files
        let mesh = try XCTUnwrap(prepared.unwrap.mesh(over: source))
        // Layer 1: red in the middle of the texture, smudged to the right.
        var red = RGBAImage.clear(width: size, height: size)
        for y in size / 4 ..< size * 3 / 4 {
            for x in size / 4 ..< size / 2 {
                red.setPixel(x, y, RGBA(0.85, 0.12, 0.1, 1))
            }
        }
        let dabs = stride(from: size / 3, through: size * 2 / 3, by: 4).map {
            PaintSmudge.Dab(center: SIMD2<Float>(Float($0), Float(size) / 2), radius: Float(size) / 12, strength: 0.7)
        }
        PaintSmudge.apply(dabs, to: &red)
        let colour = PaintOperations.tileChanges(red, layer: paint.layers[0], surface: paint.surface)
        files.merge(colour.files) { a, _ in a }
        for change in colour.changes {
            paint.layers[0].tiles[change.tile] = change.file
        }
        // A rough patch and a strip of glow on the same layer's other maps.
        var rough = RGBAImage.clear(width: size, height: size)
        var glow = RGBAImage.clear(width: size, height: size)
        for y in 0 ..< size / 4 {
            for x in 0 ..< size {
                rough.setPixel(x, y, RGBA(0.95, 0.95, 0.95, 1))
                if y < size / 16 { glow.setPixel(x, y, RGBA(1, 0.6, 0.1, 1)) }
            }
        }
        for (map, image) in [(PaintMap.roughness, rough), (.glow, glow)] {
            for (tile, picture) in PaintComposer.tiles(of: image, surface: paint.surface) {
                let png = PNGCodec.encode(picture)
                let name = PaintFiles.tileName(for: png)
                files[name] = png
                paint.layers[0][map, tile] = name
            }
        }
        // Layer 2: bricks, masked to the left half.
        let brick = try XCTUnwrap(BuiltInMaterials.material("brick"))
        let made = try XCTUnwrap(PaintOperations.addFill(.material(brick), to: paint, above: nil, object: "crate",
                                                         images: PaintFills.images(.material(brick), paintMesh: mesh, size: size)))
        files.merge(made.files) { a, _ in a }
        guard case let .setPaint(_, filled?) = made.command else { throw CommandError.empty }
        paint = filled
        var mask = RGBAImage.clear(width: size, height: size)
        for y in 0 ..< size {
            for x in 0 ..< size / 2 {
                mask.setPixel(x, y, .white)
            }
        }
        let brickLayer = paint.layers.count - 1
        paint.layers[brickLayer].maps[PaintMap.mask.rawValue] = [:]
        for (tile, picture) in PaintComposer.tiles(of: mask, surface: paint.surface) {
            let png = PNGCodec.encode(picture)
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            paint.layers[brickLayer][.mask, tile] = name
        }
        cube.paint = paint
        return (Scene(id: "s", name: "Texture", objects: ["crate": cube], roots: ["crate"]), Look(presetID: LookPreset.clay.id), files)
    }

    private func painted(_ files: [String: Data], look: Look, colors: PaintColorOutput = .texture) -> (SceneObject) -> PaintedExport? {
        { object in
            PaintExport.painted(object, source: PaintSource.mesh(of: object), base: SceneExport.material(of: object, look: look).paintBase,
                                file: { files[$0] }, colors: colors)
        }
    }

    private func glbJSON(_ glb: Data) throws -> ([String: Any], Data) {
        let bytes = [UInt8](glb)
        func u32(_ offset: Int) -> Int {
            Int(UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        let length = u32(12)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20 ..< 20 + length])) as? [String: Any])
        let start = 20 + length + 8
        return (json, Data(bytes[start ..< start + u32(20 + length)]))
    }

    private func image(_ index: Int, json: [String: Any], binary: Data) throws -> RGBAImage {
        let textures = try XCTUnwrap(json["textures"] as? [[String: Any]])
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        let source = try XCTUnwrap(textures[index]["source"] as? Int)
        let views = try XCTUnwrap(json["bufferViews"] as? [[String: Any]])
        let view = try views[XCTUnwrap(images[source]["bufferView"] as? Int)]
        let offset = try XCTUnwrap(view["byteOffset"] as? Int), length = try XCTUnwrap(view["byteLength"] as? Int)
        return try PNGCodec.decode(binary.subdata(in: offset ..< offset + length))
    }

    /// Acceptance (U7): every map leaves in the glTF, as the goldens. CI validates `textured/textured.glb` with the
    /// Khronos validator.
    func testAPaintedSmudgedMaskedModelExportsEveryMap() throws {
        let (scene, look, files) = try crate()
        let glb = GLTFScene.glb(nil, in: scene, look: look, painted: painted(files, look: look))
        let (json, binary) = try glbJSON(glb)
        let material = try XCTUnwrap((json["materials"] as? [[String: Any]])?.first)
        let pbr = try XCTUnwrap(material["pbrMetallicRoughness"] as? [String: Any])
        let maps: [(String, Int)] = try [
            ("color", XCTUnwrap((pbr["baseColorTexture"] as? [String: Any])?["index"] as? Int)),
            ("metallic-roughness", XCTUnwrap((pbr["metallicRoughnessTexture"] as? [String: Any])?["index"] as? Int)),
            ("emissive", XCTUnwrap((material["emissiveTexture"] as? [String: Any])?["index"] as? Int)),
            ("normal", XCTUnwrap((material["normalTexture"] as? [String: Any])?["index"] as? Int))
        ]
        XCTAssertEqual(pbr["roughnessFactor"] as? Double, 1, "the texture holds the roughness")
        let attributes = try XCTUnwrap(((json["meshes"] as? [[String: Any]])?.first?["primitives"] as? [[String: Any]])?.first?["attributes"]
            as? [String: Int])
        XCTAssertNotNil(attributes["TANGENT"], "a normal map needs tangents")
        XCTAssertNil(attributes["COLOR_0"], "colours as a texture, not twice")
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/texture")
        for (name, index) in maps {
            let exported = try image(index, json: json, binary: binary)
            XCTAssertEqual(exported.width, 256)
            try compare(exported, golden: golden.appendingPathComponent("\(name).png"))
        }
        // The mask: bricks on the left half of the texture only; the smudge dragged red rightward.
        let colour = try image(maps[0].1, json: json, binary: binary)
        XCTAssertNotEqual(colour.pixel(40, 40), colour.pixel(200, 40), "bricks on the left, the cube's white on the right")
        XCTAssertGreaterThan(colour.pixel(140, 128).r, colour.pixel(140, 128).g + 0.1, "red smudged past the patch's edge")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("textured")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try glb.write(to: folder.appendingPathComponent("textured.glb"))
        }
    }

    /// X1: the crate's glTF made editable again keeps its look: its pictures become a first layer, "Model", with the
    /// colour, roughness, metal and glow it left with, laid on the editable copy's own unwrap.
    func testAGLTFsPicturesComeBackAsPaint() throws {
        let (scene, look, files) = try crate()
        let glb = GLTFScene.glb(nil, in: scene, look: look, painted: painted(files, look: look))
        let (json, binary) = try glbJSON(glb)
        let material = try XCTUnwrap((json["materials"] as? [[String: Any]])?.first)
        let index = try XCTUnwrap(((material["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"] as? [String: Any])?["index"] as? Int)
        let exported = try image(index, json: json, binary: binary)
        var ids = IDFactory.sequential("t")
        let result = try GLTFSceneReader.read(glb, ids: &ids)
        let (id, pictures) = try XCTUnwrap(result.pictures.first)
        let made = result.paints(in: result.fragment, size: 256)
        XCTAssertEqual(made.commands.count, 1)
        guard case let .setPaint(target, paint?) = made.commands.first else { return XCTFail("no paint") }
        XCTAssertEqual(target, id)
        XCTAssertEqual(paint.layers.map(\.name), ["Model", "Layer 1"])
        let model = paint.layers[0]
        XCTAssertEqual(Set(model.paintedMaps), [.color, .roughness, .metal, .glow])
        // Each of the model's triangles: its colour in the exported picture, and on the new surface at the same point.
        let unwrapData = try XCTUnwrap(made.files[paint.surface.unwrap])
        let surface = try PaintUnwrap(data: unwrapData).surfaceMesh
        let grid = TriangleGrid(surface, cell: 0.05)
        var tiles: [String: RGBAImage] = [:]
        func paintedColor(_ uv: SIMD2<Float>) throws -> RGBA? {
            let x = min(Int(uv.x * 256), 255), y = min(Int(uv.y * 256), 255)
            guard let name = model[.color, PaintTileIndex(column: x / 256, row: y / 256)] else { return nil }
            if tiles[name] == nil { tiles[name] = try PNGCodec.decode(XCTUnwrap(made.files[name])) }
            return tiles[name]?.pixel(x % 256, y % 256)
        }
        let source = pictures.source
        var close = 0, total = 0
        for face in 0 ..< source.triangleCount {
            let corners = (0 ..< 3).map { Int(source.indices[face * 3 + $0]) }
            let point = corners.map { source.positions[$0] }.reduce(SIMD3<Float>.zero, +) / 3
            let uv = corners.map { source.uvs[$0] }.reduce(SIMD2<Float>.zero, +) / 3
            let expected = exported.sample(u: Double(uv.x), v: Double(uv.y))
            guard let hit = grid.closest(to: point, within: 0.05, hint: nil) else { continue }
            let at = (0 ..< 3).map { surface.uvs[Int(surface.indices[hit.triangle * 3 + $0])] }
            let newUV = at[0] * hit.weights.x + at[1] * hit.weights.y + at[2] * hit.weights.z
            guard let found = try paintedColor(newUV) else { continue }
            total += 1
            if max(abs(found.r - expected.r), abs(found.g - expected.g), abs(found.b - expected.b)) < 0.1 { close += 1 }
        }
        XCTAssertGreaterThan(total, source.triangleCount / 2)
        XCTAssertGreaterThanOrEqual(Double(close) / Double(max(total, 1)), 0.9, "\(close) of \(total) points kept their colour")
        // The normal map: the same bumps in the new surface's frames (each texel back in the object's space agrees).
        let normalIndex = try XCTUnwrap((material["normalTexture"] as? [String: Any])?["index"] as? Int)
        let exportedNormals = try image(normalIndex, json: json, binary: binary)
        let normals = try PNGCodec.decode(XCTUnwrap(paint.normalMap.flatMap { made.files[$0] }))
        let sourceFrames = NormalBake.triangleFrames(source), frames = NormalBake.triangleFrames(surface)
        func world(_ texel: RGBA, frame: (SIMD3<Float>, SIMD3<Float>), normal: SIMD3<Float>) -> SIMD3<Float> {
            let t = SIMD3<Float>(Float(texel.r), Float(texel.g), Float(texel.b)) * 2 - 1
            let (tangent, bitangent) = NormalBake.orthonormal(frame, normal: normal)
            return normalize3(tangent * t.x + bitangent * t.y + normal * t.z, fallback: normal)
        }
        var agree = 0, compared = 0
        for face in 0 ..< source.triangleCount {
            let corners = (0 ..< 3).map { source.positions[Int(source.indices[face * 3 + $0])] }
            let point = corners.reduce(SIMD3<Float>.zero, +) / 3
            let facing = normalize3(cross3(corners[1] - corners[0], corners[2] - corners[0]), fallback: SIMD3<Float>(0, 1, 0))
            let uv = (0 ..< 3).map { source.uvs[Int(source.indices[face * 3 + $0])] }.reduce(SIMD2<Float>.zero, +) / 3
            guard let hit = grid.closest(to: point, within: 0.05, hint: nil) else { continue }
            let at = (0 ..< 3).map { surface.uvs[Int(surface.indices[hit.triangle * 3 + $0])] }
            let newUV = at[0] * hit.weights.x + at[1] * hit.weights.y + at[2] * hit.weights.z
            let before = world(exportedNormals.sample(u: Double(uv.x), v: Double(uv.y)), frame: sourceFrames[face], normal: facing)
            let after = world(normals.sample(u: Double(newUV.x), v: Double(newUV.y)), frame: frames[hit.triangle], normal: facing)
            compared += 1
            if dot3(before, after) > 0.96 { agree += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(agree) / Double(max(compared, 1)), 0.9, "\(agree) of \(compared) normals agree")
    }

    func testATextureTransformMovesTheUVs() {
        let moved = GLTFSceneReader.Builder.transformed(SIMD2<Float>(1, 0), by: ["offset": [0.5, 0.25], "scale": [2.0, 3.0], "rotation": Double.pi / 2])
        // Scaled to (2, 0), turned a quarter (u' = cos·u + sin·v, v' = -sin·u + cos·v) to (0, -2), then offset.
        XCTAssertEqual(moved.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(moved.y, -1.75, accuracy: 1e-5)
    }

    /// Exact to a step of rounding; `RECORD_GOLDEN=1` writes the golden instead (reviewed, then committed).
    private func compare(_ image: RGBAImage, golden url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        if ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PNGCodec.encode(image).write(to: url)
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            return XCTFail("No golden at \(url.lastPathComponent): run once with RECORD_GOLDEN=1", file: file, line: line)
        }
        let expected = try PNGCodec.decode(data)
        XCTAssertEqual(expected.width, image.width, file: file, line: line)
        let worst = zip(expected.pixels, image.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 1, "\(url.lastPathComponent) differs from its golden by \(worst)", file: file, line: line)
    }

    func testUSDZCarriesTheMapsAndAPNGSetNamesThem() throws {
        let (scene, look, files) = try crate()
        let meshes = SceneExport.meshes(nil, in: scene, look: look, painted: painted(files, look: look))
        let usda = SceneExport.usda(meshes)
        XCTAssertTrue(usda.contains("inputs:roughness.connect"))
        XCTAssertTrue(usda.contains("inputs:emissiveColor.connect"))
        XCTAssertTrue(usda.contains("normal3f inputs:normal.connect"))
        XCTAssertTrue(usda.contains("float4 inputs:scale = (2, 2, 2, 1)"))
        let names = try ZipReader.entries(SceneExport.usdz(meshes)).map(\.name)
        XCTAssertTrue(names.contains("textures/paint_0_roughness.png"))
        XCTAssertTrue(names.contains("textures/paint_0_normal.png"))
        let export = try XCTUnwrap(painted(files, look: look)(XCTUnwrap(scene.objects["crate"])))
        XCTAssertEqual(PaintExport.pngSet(export, name: "Crate").map(\.0),
                       ["Crate_color.png", "Crate_roughness.png", "Crate_metal.png", "Crate_emissive.png", "Crate_normal.png"])
    }

    func testColoursCanLeaveAsVertexColoursOrAPalette() throws {
        let (scene, look, files) = try crate()
        let glb = GLTFScene.glb(nil, in: scene, look: look, painted: painted(files, look: look, colors: .vertexColors))
        let (json, _) = try glbJSON(glb)
        let primitive = try XCTUnwrap(((json["meshes"] as? [[String: Any]])?.first?["primitives"] as? [[String: Any]])?.first)
        XCTAssertNotNil((primitive["attributes"] as? [String: Int])?["COLOR_0"])
        let pbr = try XCTUnwrap((json["materials"] as? [[String: Any]])?.first?["pbrMetallicRoughness"] as? [String: Any])
        XCTAssertNil(pbr["baseColorTexture"], "vertex colours carry the colour alone")
        let object = try XCTUnwrap(scene.objects["crate"])
        let palette = try XCTUnwrap(painted(files, look: look, colors: .palette)(object))
        let picture = try PNGCodec.decode(palette.texture)
        XCTAssertLessThan(picture.width, 64, "a small picture of swatches")
        XCTAssertEqual(palette.mesh.positions.count, palette.mesh.indices.count, "each triangle on its own swatch")
        XCTAssertTrue(palette.maps.isEmpty)
    }

    func testFurLeavesAsCutOutCardsOrShells() throws {
        var fluffy = SceneObject(id: "f", name: "Fluffy", kind: .primitive(.sphere))
        fluffy[.color] = .color(.rgba(RGBA(0.8, 0.5, 0.2)))
        fluffy[.furLength] = .float(0.05)
        let scene = Scene(id: "s", name: "Fur", objects: ["f": fluffy], roots: ["f"])
        let look = Look(presetID: LookPreset.clay.id)
        let (shells, _) = try glbJSON(GLTFScene.glb(nil, in: scene, look: look))
        let primitives = try XCTUnwrap((shells["meshes"] as? [[String: Any]])?.first?["primitives"] as? [[String: Any]])
        XCTAssertEqual(primitives.count, 9, "the surface and eight shells")
        let materials = try XCTUnwrap(shells["materials"] as? [[String: Any]])
        XCTAssertEqual(materials.last?["alphaMode"] as? String, "MASK")
        XCTAssertEqual(materials.last?["doubleSided"] as? Bool, true)
        var cards = scene
        cards.objects["f"]?[.furStyle] = .enumeration("cards")
        let (json, _) = try glbJSON(GLTFScene.glb(nil, in: cards, look: look))
        XCTAssertEqual((json["meshes"] as? [[String: Any]])?.first.flatMap { ($0["primitives"] as? [[String: Any]])?.count }, 2,
                       "the surface and its hair cards")
    }

    // MARK: The bridge

    private func bridgeDocument() -> Document {
        var document = makeDocument()
        var high = SceneObject(id: "hi", name: "Sculpt", kind: .primitive(.sphere), transform: Transform(position: Vec3(1, 0, 0)))
        high[.color] = .color(.rgba(.white))
        document.scene.objects["hi"] = high
        document.scene.roots.append("hi")
        return document
    }

    private func compile(_ actions: [String], document: Document, files: [String: Data] = [:]) throws -> ScriptResult {
        let json = "{\"title\":\"Texture\",\"version\":3,\"actions\":[\(actions.joined(separator: ","))]}"
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        let known = files
        return try ScriptCompiler.compile(script, document: document, context: ScriptContext(ids: .sequential("t"), file: { known[$0] }))
    }

    func testTheBridgeTexturesAThing() throws {
        let document = bridgeDocument()
        let result = try compile([
            ##"{"do":"paint","target":"C","op":"size","pixels":512}"##,
            ##"{"do":"paint","target":"C","op":"material","material":"oak","scale":0.5}"##,
            ##"{"do":"paint","target":"C","op":"wear","kind":"edges","amount":0.7}"##,
            ##"{"do":"paint","target":"C","op":"color","color":"#336699"}"##,
            ##"{"do":"paint","target":"C","op":"mask","layer":4}"##,
            ##"{"do":"paint","target":"C","op":"mirror","axis":"x"}"##,
            ##"{"do":"paint","target":"C","op":"fur","length":0.02,"style":"cards"}"##,
            ##"{"do":"paint","target":"C","op":"layers"}"##
        ], document: document)
        let paint = try XCTUnwrap(result.document.scene.objects["c"]?.paint)
        XCTAssertEqual(paint.surface.size, 512)
        XCTAssertEqual(paint.layers.map(\.name), ["Layer 1", "Oak", "Worn edges", "Colour fill"])
        XCTAssertTrue(paint.layers[3].hasMask)
        XCTAssertEqual(paint.mirror, .x)
        XCTAssertEqual(result.document.scene.objects["c"]?[.furStyle]?.stringValue, "cards")
        XCTAssertTrue(paint.files.isSubset(of: Set(result.files.keys)), "every file the paint names comes with it")
        XCTAssertTrue(result.report.contains { $0.hasPrefix("4. Colour fill") && $0.contains("masked") })
        // One undo step, and it reverts.
        let command = try XCTUnwrap(result.command)
        try assertReverts(command, on: document)
    }

    func testTheBridgePlacesDecalsFacesSeamsAndNormals() throws {
        let document = bridgeDocument()
        let picture = PNGCodec.encode(RGBAImage(width: 4, height: 4, color: RGBA(1, 0, 1, 1)))
        let result = try compile([
            ##"{"do":"paint","target":"A","op":"size","pixels":512}"##,
            ##"{"do":"paint","target":"A","op":"decal","picture":"media/logo.png","at":[1,0.5,0.5],"facing":[0,0,1],"size":0.4}"##,
            ##"{"do":"paint","target":"A","op":"faces","at":[1,1,0],"color":"#22AA44"}"##,
            ##"{"do":"paint","target":"A","op":"seams","edges":[[[0.5,1,-0.5],[1.5,1,-0.5]],[[1.5,1,-0.5],[1.5,1,0.5]],"##
                + ##"[[1.5,1,0.5],[0.5,1,0.5]],[[0.5,1,0.5],[0.5,1,-0.5]]]}"##,
            ##"{"do":"paint","target":"A","op":"bakeNormals","from":"Sculpt"}"##
        ], document: document, files: ["media/logo.png": picture])
        let paint = try XCTUnwrap(result.document.scene.objects["a"]?.paint)
        XCTAssertEqual(paint.layers.last?.name, "Decal")
        XCTAssertFalse(paint.layers.last?.tiles.isEmpty ?? true)
        XCTAssertEqual(paint.surface.seams?.count, 4)
        XCTAssertEqual(paint.normalsFrom, "Sculpt")
        XCTAssertNotNil(paint.normalMap.flatMap { result.files[$0] })
        XCTAssertThrowsError(try compile([##"{"do":"paint","target":"A","op":"sparkle"}"##], document: document))
        XCTAssertThrowsError(try compile([##"{"do":"paint","target":"A","op":"material","material":"cheese"}"##], document: document))
        XCTAssertThrowsError(try compile([##"{"do":"paint","target":"A","op":"decal","picture":"missing.png","at":[1,0.5,0.5]}"##], document: document))
    }
}
