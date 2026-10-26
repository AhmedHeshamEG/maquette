import Foundation
@testable import LoweyCore
import XCTest

/// Clones in glTF (X1): out as GPU instances where the copies stand, back as the same recipe through Maquette, and as
/// placed clones from any other tool's instances.
final class GLTFCloneTests: XCTestCase {
    /// A cube in a ring of six, facing out, scattered a little, its parent turned so the places aren't trivially the world's.
    static func ringScene() -> Scene {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube), parent: "stand",
                               transform: Transform(position: Vec3(0, 1, 0), scale: Vec3(0.5, 0.5, 0.5)))
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .circle(count: 6, radius: 3, facesOut: true),
                                                              effects: [CloneEffect(id: "e", kind: .random, move: Vec3(0, 0.4, 0))], seed: 7))
        var stand = SceneObject(id: "stand", name: "Stand", kind: .group, transform: Transform(rotation: Quat(angle: 0.4, axis: .unitY)))
        stand.children = ["cube"]
        return Scene(id: "s", name: "Ring", objects: ["stand": stand, "cube": cube], roots: ["stand"])
    }

    func testClonesLeaveAsInstancesAndComeBackAsTheirRecipe() throws {
        let scene = Self.ringScene()
        let glb = GLTFScene.glb(nil, in: scene, look: Look())
        let (json, _) = try Self.split(glb)
        XCTAssertTrue((json["extensionsUsed"] as? [String])?.contains("EXT_mesh_gpu_instancing") == true)
        let node = try XCTUnwrap((json["nodes"] as? [[String: Any]])?.first { $0["name"] as? String == "Cube" })
        let attributes = try XCTUnwrap(((node["extensions"] as? [String: Any])?["EXT_mesh_gpu_instancing"] as? [String: Any])?["attributes"]
            as? [String: Int])
        let accessors = try XCTUnwrap(json["accessors"] as? [[String: Any]])
        XCTAssertEqual(try accessors[XCTUnwrap(attributes["TRANSLATION"])]["count"] as? Int, 6)
        // Back through Maquette: the same recipe, so the effect still plays.
        var ids = IDFactory.sequential("r")
        let read = try GLTFSceneReader.read(glb, ids: &ids)
        let cube = try XCTUnwrap(read.fragment.objects.first { $0.name == "Cube" })
        XCTAssertEqual(cube.motionDesign?.clones, scene.objects["cube"]?.motionDesign?.clones)
    }

    /// Another tool's instances (no recipe): placed clones whose copies stand exactly where the instances did.
    func testAnotherToolsInstancesComeInPlaced() throws {
        let scene = Self.ringScene()
        let glb = GLTFScene.glb(nil, in: scene, look: Look())
        var (json, binary) = try Self.split(glb)
        var nodes = try XCTUnwrap(json["nodes"] as? [[String: Any]])
        for index in nodes.indices {
            nodes[index]["extras"] = nil
        }
        json["nodes"] = nodes
        let foreign = try Self.pack(json, binary)
        var ids = IDFactory.sequential("f")
        let read = try GLTFSceneReader.read(foreign, ids: &ids)
        let thing = try XCTUnwrap(read.fragment.objects.first { $0.motionDesign?.clones != nil })
        let clones = try XCTUnwrap(thing.motionDesign?.clones)
        guard case .placed = clones.layout else { return XCTFail("placed, not \(clones.layout.title)") }
        XCTAssertEqual(clones.count, 6)
        // Every copy where Maquette put it, in the node's space.
        let expected = try GLTFSceneWriter.clonePlaces(of: XCTUnwrap(scene.objects["cube"]), clones: XCTUnwrap(scene.objects["cube"]?.motionDesign?.clones),
                                                       in: scene)
        let got = GLTFSceneWriter.clonePlaces(of: thing, clones: clones, in: Scene(id: "t", name: "T"))
        // A ring's first copy isn't at the thing's own place, so the read thing stands at it, under the node.
        XCTAssertEqual(got.count, expected.count)
        for (want, have) in zip(expected, got) {
            let placed = thing.transform * have
            XCTAssertTrue(want.isApproximately(placed, tolerance: 1e-4), "\(want) vs \(placed)")
        }
    }

    static func split(_ glb: Data) throws -> ([String: Any], Data) {
        let bytes = [UInt8](glb)
        func u32(_ offset: Int) -> Int {
            Int(UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        let length = u32(12)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20 ..< 20 + length])) as? [String: Any])
        let start = 20 + length + 8
        return (json, Data(bytes[start ..< start + u32(20 + length)]))
    }

    static func pack(_ json: [String: Any], _ binary: Data) throws -> Data {
        var text = try JSONSerialization.data(withJSONObject: json)
        while text.count % 4 != 0 {
            text.append(0x20)
        }
        var bin = binary
        while bin.count % 4 != 0 {
            bin.append(0)
        }
        var data = Data()
        func put(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("glTF".utf8))
        put(2)
        put(12 + 8 + text.count + 8 + bin.count)
        put(text.count)
        data.append(contentsOf: Array("JSON".utf8))
        data.append(text)
        put(bin.count)
        data.append(contentsOf: [0x42, 0x49, 0x4E, 0x00])
        data.append(bin)
        return data
    }
}
