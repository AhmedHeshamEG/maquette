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
        XCTAssertEqual(objects.filter { $0.name.hasPrefix("Trees ") }.count, 3)
        let tree = try XCTUnwrap(objects.first { $0.name == "Trees 2" })
        XCTAssertEqual(tree.transform.position.x, 1.5, accuracy: 1e-9)
        XCTAssertEqual(tree.color?.resolved(in: .empty), RGBA.hex("#2E8B57"))
        XCTAssertNotNil(objects.first { $0.name == "Sea" })
        XCTAssertNil(objects.first { $0.name == "Sky light" || $0.name == "Spray" })
        XCTAssertEqual(objects.first { $0.name == "Sun" }?.kind, .light(.directional))
        let spin = try XCTUnwrap(result.scene.tracks.first { $0.property == .rotation })
        XCTAssertEqual(spin.keyframes.count, 3)
        XCTAssertEqual(result.scene.duration, 4)
        XCTAssertTrue(result.suggestsToon)
        XCTAssertEqual(result.notes.count, 5, result.notes.joined(separator: "\n"))
        // In the scene as one step.
        let command = ModelingOperations.importScene(result.scene, in: Scene(id: "s", name: "Empty"))
        guard case let .batch(label, _) = command else { return XCTFail("one step") }
        XCTAssertEqual(label, "Import")
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
