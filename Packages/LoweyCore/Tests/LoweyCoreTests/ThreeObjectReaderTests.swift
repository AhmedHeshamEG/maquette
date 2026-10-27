import Foundation
@testable import LoweyCore
import XCTest

/// three.js's own scene format in (X1 step 3).
final class ThreeObjectReaderTests: XCTestCase {
    /// Acceptance (X1 matrix: three.js JSON ▸ In): Maquette's scene out as `scene.json` and back keeps its things, their
    /// names, places, materials, cameras, lights and every key three.js can hold.
    func testAScenesJSONComesBackAsItWas() throws {
        let scene = ThreeProjectTests.webScene()
        let json = try ThreeObjectJSON.data(fromGLB: ThreeNames.prepared(GLTFScene.glb(nil, in: scene, look: Look())))
        var ids = IDFactory.sequential("in")
        let result = try ThreeObjectReader.read(json, ids: &ids)
        let objects = result.scene.fragment.objects
        let byName = Dictionary(objects.map { ($0.name, $0) }) { first, _ in first }
        // Maquette's own names come back, not three.js's.
        XCTAssertNotNil(byName["Coffee table"])
        XCTAssertEqual(objects.filter { $0.name == "Top" }.count, 2)
        XCTAssertFalse(objects.contains { $0.name.hasSuffix("_target") }, "a light's aim isn't a thing")
        for (id, name) in [("table", "Coffee table"), ("lantern", "Lantern"), ("cam", "Shot"), ("spot", "Spot")] {
            let back = try XCTUnwrap(byName[name])
            XCTAssertTrue(back.transform.isApproximately(scene.objects[ObjectID(raw: id)]?.transform ?? .identity, tolerance: 1e-4), name)
        }
        let lantern = try XCTUnwrap(byName["Lantern"])
        guard case let .mesh(shape) = lantern.kind else { return XCTFail("the lantern is a mesh") }
        XCTAssertEqual(shape.volume, 1, accuracy: 1e-3)
        XCTAssertEqual(lantern.color?.resolved(in: .empty), RGBA(0.9, 0.6, 0.2))
        XCTAssertEqual(byName["Spot"]?.kind, .light(.spot))
        XCTAssertEqual(byName["Spot"]?[.spotAngle]?.floatValue ?? 0, 30, accuracy: 1e-3)
        XCTAssertEqual(byName["Shot"]?[.fieldOfView]?.floatValue ?? 0, 50, accuracy: 1e-3)
        // Every key three.js holds plays the same (the face state stays behind: three.js has no place for it).
        let names = Dictionary(objects.map { ($0.id, $0.name) }) { first, _ in first }
        for original in scene.timeline.tracks where original.property != .jawOpen {
            let name = scene.objects[original.target]?.name ?? ""
            let copy = try XCTUnwrap(result.scene.tracks.first { names[$0.target] == name && $0.property == original.property },
                                     "\(name) \(original.property)")
            for time in stride(from: 0.0, through: 2, by: 0.25) {
                try GLTFPointerTests.assertSame(original.value(at: time), copy.value(at: time), "\(name) \(original.property) at \(time)")
            }
        }
    }

    /// Acceptance (X1): a vibe-coded island comes in as editable things, its spin as keys; what can't come is said.
    func testAVibeCodedIslandComesInAsThings() throws {
        var ids = IDFactory.sequential("in")
        let result = try ThreeObjectReader.read(Data(Self.island.utf8), ids: &ids)
        let objects = result.scene.fragment.objects
        let island = try XCTUnwrap(objects.first { $0.name == "Island" })
        guard case let .mesh(rock) = island.kind else { return XCTFail("the island is a mesh") }
        XCTAssertEqual(rock.volume, 4 * 1 * 4, accuracy: 1e-6)
        // The forest is one tree, cloned where the instances stand.
        let tree = try XCTUnwrap(objects.first { $0.motionDesign?.clones != nil })
        XCTAssertEqual(tree.transform.position.x, -1, accuracy: 1e-9)
        XCTAssertEqual(tree.color?.resolved(in: .empty), RGBA.hex("#2E8B57"))
        let clones = try XCTUnwrap(tree.motionDesign?.clones)
        XCTAssertEqual(clones.count, 3)
        let slots = ClonePlayback.slots(clones.layout, count: clones.count, base: tree.transform, parent: tree.parent, in: Scene(id: "s", name: "S"))
        let played = slots.enumerated().map { index, slot in
            ClonePlayback.transform(slot: slot, index: index, clones: clones, base: tree.transform, moved: tree.transform, time: 0, strength: 1).position
        }
        XCTAssertEqual(played.map(\.x), [-1, 1.5, 0])
        XCTAssertEqual(played.map(\.z), [0, 0, 1])
        XCTAssertNotNil(objects.first { $0.name == "Sea" })
        XCTAssertNil(objects.first { $0.name == "Sky light" || $0.name == "Spray" })
        XCTAssertEqual(objects.first { $0.name == "Sun" }?.kind, .light(.directional))
        let spin = try XCTUnwrap(result.scene.tracks.first { $0.property == .rotation })
        XCTAssertEqual(spin.keyframes.count, 3)
        XCTAssertEqual(result.scene.duration, 4)
        XCTAssertTrue(result.suggestsToon)
        XCTAssertEqual(result.notes.count, 4, result.notes.joined(separator: "\n"))
        // In the scene as one step.
        let command = ModelingOperations.importScene(result.scene, in: Scene(id: "s", name: "Empty"))
        guard case let .batch(label, _) = command else { return XCTFail("one step") }
        XCTAssertEqual(label, "Import")
    }

    /// A skinned arm comes in rigged: two bones in their bind places, the weights on the surface, the elbow's turn as
    /// keys, and no bones as things.
    func testASkinnedMeshComesInRigged() throws {
        let json = """
        {"metadata":{"version":4.6,"type":"Object","generator":"Object3D.toJSON"},
         "geometries":[{"uuid":"g","type":"BufferGeometry","data":{"attributes":{
           "position":{"itemSize":3,"type":"Float32Array","array":[0,0,0, 1,0,0, 2,0,0, 0,0.2,0, 1,0.2,0, 2,0.2,0]},
           "skinIndex":{"itemSize":4,"type":"Uint16Array","array":[0,0,0,0, 0,1,0,0, 1,0,0,0, 0,0,0,0, 0,1,0,0, 1,0,0,0]},
           "skinWeight":{"itemSize":4,"type":"Float32Array","array":[1,0,0,0, 0.5,0.5,0,0, 1,0,0,0, 1,0,0,0, 0.5,0.5,0,0, 1,0,0,0]}},
           "index":{"type":"Uint16Array","array":[0,1,4, 0,4,3, 1,2,5, 1,5,4]}}}],
         "materials":[{"uuid":"m","type":"MeshStandardMaterial","color":16777215}],
         "skeletons":[{"uuid":"k","bones":["b1","b2"],"boneInverses":[[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-1,0,0,1]]}],
         "object":{"uuid":"s","type":"Scene","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"animations":["c"],"children":[
           {"uuid":"o","type":"SkinnedMesh","name":"Arm","geometry":"g","material":"m","skeleton":"k","bindMode":"attached",
            "bindMatrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"children":[
             {"uuid":"b1","type":"Bone","name":"Upper","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"children":[
               {"uuid":"b2","type":"Bone","name":"Lower","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,1,0,0,1]}]}]}]},
         "animations":[{"uuid":"c","name":"wave","duration":1,"tracks":[
           {"name":"Lower.quaternion","type":"quaternion","times":[0,1],"values":[0,0,0,1, 0,0,0.7071068,0.7071068]}]}]}
        """
        var ids = IDFactory.sequential("k")
        let result = try ThreeObjectReader.read(Data(json.utf8), ids: &ids)
        XCTAssertFalse(result.notes.contains { $0.hasPrefix("Skinned") }, result.notes.joined(separator: " "))
        let objects = result.scene.fragment.objects
        XCTAssertFalse(objects.contains { $0.name == "Upper" || $0.name == "Lower" }, "bones aren't things")
        let arm = try XCTUnwrap(objects.first { $0.name == "Arm" })
        let rig = try XCTUnwrap(arm.rig)
        XCTAssertEqual(rig.skeleton.names, ["Upper", "Lower"])
        XCTAssertEqual(rig.skeleton.modelRest[1].position.x, 1, accuracy: 1e-9)
        let weights = try SkinWeights(data: XCTUnwrap(rig.skin.flatMap { result.scene.files[$0] }))
        let surface = try XCTUnwrap(PaintSource.unshaped(of: arm))
        let far = try XCTUnwrap(surface.positions.indices.max { surface.positions[$0].x < surface.positions[$1].x })
        XCTAssertGreaterThan(weights.weight(of: 1, at: far), 0.9, "the hand's end follows the elbow")
        let wave = try XCTUnwrap(result.scene.tracks.first { $0.property == .boneTurn("Lower") })
        XCTAssertEqual(wave.target, arm.id)
        XCTAssertEqual(wave.keyframes.count, 2)
    }

    /// A picture the file carries comes in as paint: a sign, red on its left, blue on its right.
    func testAPictureInTheFileComesInAsPaint() throws {
        var picture = RGBAImage.clear(width: 4, height: 4)
        for y in 0 ..< 4 {
            for x in 0 ..< 4 {
                picture.setPixel(x, y, x < 2 ? RGBA(1, 0, 0, 1) : RGBA(0, 0, 1, 1))
            }
        }
        let url = "data:image/png;base64," + PNGCodec.encode(picture).base64EncodedString()
        let json = """
        {"metadata":{"version":4.6,"type":"Object","generator":"Object3D.toJSON"},
         "geometries":[{"uuid":"g","type":"BufferGeometry","data":{"attributes":{
           "position":{"itemSize":3,"type":"Float32Array","array":[0,0,0, 2,0,0, 2,1,0, 0,1,0]},
           "uv":{"itemSize":2,"type":"Float32Array","array":[0,0, 1,0, 1,1, 0,1]}},
           "index":{"type":"Uint16Array","array":[0,1,2, 0,2,3]}}}],
         "materials":[{"uuid":"m","type":"MeshStandardMaterial","color":16777215,"roughness":0.5,"metalness":0,"map":"t"}],
         "textures":[{"uuid":"t","image":"i","repeat":[1,1],"offset":[0,0],"center":[0,0],"rotation":0,"flipY":true}],
         "images":[{"uuid":"i","url":"\(url)"}],
         "object":{"uuid":"s","type":"Scene","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"children":[
           {"uuid":"o","type":"Mesh","name":"Sign","geometry":"g","material":"m","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}]}}
        """
        var ids = IDFactory.sequential("p")
        let result = try ThreeObjectReader.read(Data(json.utf8), ids: &ids)
        XCTAssertFalse(result.notes.contains { $0.hasPrefix("Pictures") }, result.notes.joined(separator: " "))
        let sign = try XCTUnwrap(result.scene.fragment.objects.first { $0.name == "Sign" })
        XCTAssertNotNil(result.scene.pictures[sign.id])
        let made = result.scene.paints(in: result.scene.fragment, size: 256)
        guard case let .setPaint(_, paint?) = made.commands.first else { return XCTFail("no paint") }
        let model = paint.layers[0]
        XCTAssertEqual(model.name, "Model")
        // Where the sign's left and right ends lie on the new surface, and their colours there.
        let surface = try PaintUnwrap(data: XCTUnwrap(made.files[paint.surface.unwrap])).surfaceMesh
        func colour(at point: SIMD3<Float>) throws -> RGBA {
            let grid = TriangleGrid(surface, cell: 0.2)
            let hit = try XCTUnwrap(grid.closest(to: point, within: 0.2, hint: nil))
            let corners = (0 ..< 3).map { surface.uvs[Int(surface.indices[hit.triangle * 3 + $0])] }
            let uv = corners[0] * hit.weights.x + corners[1] * hit.weights.y + corners[2] * hit.weights.z
            let x = min(Int(uv.x * 256), 255), y = min(Int(uv.y * 256), 255)
            let name = try XCTUnwrap(model[.color, PaintTileIndex(column: 0, row: 0)])
            return try PNGCodec.decode(XCTUnwrap(made.files[name])).pixel(x, y)
        }
        let left = try colour(at: SIMD3<Float>(0.3, 0.5, 0)), right = try colour(at: SIMD3<Float>(1.7, 0.5, 0))
        XCTAssertGreaterThan(left.r, 0.9)
        XCTAssertLessThan(left.b, 0.1)
        XCTAssertGreaterThan(right.b, 0.9)
        XCTAssertLessThan(right.r, 0.1)
        // three.js's uv transform: repeat about the centre, then the flip.
        let moved = ThreeReaderBuilder.placed(SIMD2<Float>(0.25, 0.25), by: ["repeat": [2.0, 2.0], "center": [0.5, 0.5], "offset": [0.1, 0.0]])
        XCTAssertEqual(moved.x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(moved.y, 1, accuracy: 1e-6)
    }

    /// What `scene.toJSON()` writes for a small island an agent made: parametric geometries, toon and shader materials,
    /// an instanced forest, lights three.js has and Maquette doesn't, and a spinning clip.
    static let island = """
    {"metadata":{"version":4.6,"type":"Object","generator":"Object3D.toJSON"},
     "geometries":[{"uuid":"g-rock","type":"BoxGeometry","width":4,"height":1,"depth":4},
                   {"uuid":"g-tree","type":"ConeGeometry","radius":0.4,"height":1.2},
                   {"uuid":"g-sea","type":"PlaneGeometry","width":20,"height":20},
                   {"uuid":"g-spray","type":"BufferGeometry","data":{"attributes":{"position":{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,1,1]}}}}],
     "materials":[{"uuid":"m-rock","type":"MeshToonMaterial","color":9139029},
                  {"uuid":"m-tree","type":"MeshStandardMaterial","color":3050327,"roughness":0.9,"metalness":0},
                  {"uuid":"m-sea","type":"ShaderMaterial","uniforms":{},"vertexShader":"void main(){}","fragmentShader":"void main(){}"}],
     "object":{"uuid":"scene","type":"Scene","name":"","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"animations":["clip"],"children":[
       {"uuid":"o-island","type":"Mesh","name":"Island","geometry":"g-rock","material":"m-rock","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0.5,0,1],
        "children":[{"uuid":"o-trees","type":"InstancedMesh","name":"Trees","geometry":"g-tree","material":"m-tree","count":3,
          "matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1],
          "instanceMatrix":{"itemSize":16,"type":"Float32Array","array":[1,0,0,0,0,1,0,0,0,0,1,0,-1,0,0,1, 1,0,0,0,0,1,0,0,0,0,1,0,1.5,0,0,1, 1,0,0,0,0,1,0,0,0,0,1,0,0,0,1,1]}}]},
       {"uuid":"o-sea","type":"Mesh","name":"Sea","geometry":"g-sea","material":"m-sea","matrix":[1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1]},
       {"uuid":"o-spray","type":"Points","name":"Spray","geometry":"g-spray","material":"m-sea","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
       {"uuid":"o-ambient","type":"AmbientLight","name":"Sky light","color":16777215,"intensity":0.5,"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
       {"uuid":"o-sun","type":"DirectionalLight","name":"Sun","color":16772829,"intensity":2,"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,5,10,5,1]}]},
     "animations":[{"uuid":"clip","name":"spin","duration":4,"blendMode":2500,"tracks":[
       {"name":"Island.quaternion","type":"quaternion","times":[0,2,4],"values":[0,0,0,1, 0,1,0,0, 0,0,0,1]}]}]}
    """
}
