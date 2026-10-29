import Foundation
@testable import LoweyCore
import XCTest

/// Keys on more than a place (X1): materials, lights and lenses as `KHR_animation_pointer`, everything else kept in the
/// file's extras, and all of it back as keys.
final class GLTFPointerTests: XCTestCase {
    /// A lantern that fades in and glows brighter than white, a spot that opens up, a lens that zooms, and a face
    /// state glTF has no place for.
    static func keyedScene() -> Scene {
        var lantern = SceneObject(id: "lantern", name: "Lantern", kind: .primitive(.cube))
        lantern[.color] = .color(.rgba(RGBA(0.9, 0.6, 0.2)))
        lantern[.emissive] = .color(.rgba(RGBA(1, 0.8, 0.4)))
        lantern[.emissiveIntensity] = .float(0.5)
        var spot = SceneObject(id: "spot", name: "Spot", kind: .light(.spot), transform: Transform(position: Vec3(0, 3, 0)))
        spot[.spotAngle] = .float(30)
        var camera = SceneObject(id: "cam", name: "Shot", kind: .camera, transform: Transform(position: Vec3(0, 1.5, 6)))
        camera[.fieldOfView] = .float(50)
        func track(_ id: String, _ target: ObjectID, _ property: PropertyKey, _ values: [PropertyValue], easing: Easing = .linear) -> Track {
            Track(id: TrackID(raw: id), target: target, property: property,
                  keyframes: values.enumerated().map { Keyframe(time: Double($0.offset), value: $0.element, easing: easing) })
        }
        let tracks = [
            track("c", "lantern", .color, [.color(.rgba(RGBA(0.9, 0.6, 0.2))), .color(.rgba(RGBA(0.2, 0.5, 0.9)))]),
            track("o", "lantern", .opacity, [.float(0.25), .float(1)]),
            track("r", "lantern", .roughness, [.float(0.9), .float(0.2), .float(0.6)]),
            track("g", "lantern", .emissiveIntensity, [.float(0.5), .float(3)]),
            track("i", "spot", .lightIntensity, [.float(1), .float(8)], easing: .step),
            track("a", "spot", .spotAngle, [.float(30), .float(70)]),
            track("f", "cam", .fieldOfView, [.float(50), .float(24)]),
            track("j", "lantern", .jawOpen, [.float(0), .float(1)])
        ]
        return Scene(id: "s", name: "Night", objects: ["lantern": lantern, "spot": spot, "cam": camera], roots: ["lantern", "spot", "cam"],
                     timeline: Timeline(fps: 24, duration: 2, tracks: tracks))
    }

    func testKeyedMaterialsLightsAndLensesPointAtTheirNumbers() throws {
        let glb = GLTFScene.glb(nil, in: Self.keyedScene(), look: Look())
        let file = try GLTFReader.parse(glb, baseURL: nil)
        let used = file.json["extensionsUsed"] as? [String] ?? []
        XCTAssertTrue(used.contains("KHR_animation_pointer"))
        XCTAssertTrue(used.contains("KHR_materials_emissive_strength"))
        // Pointers are only used: a reader without them still opens the file.
        XCTAssertNil(file.json["extensionsRequired"])
        let channels = (file.array("animations").first?["channels"] as? [[String: Any]]) ?? []
        let pointers = Set(channels.compactMap { channel -> String? in
            let target = channel["target"] as? [String: Any]
            return ((target?["extensions"] as? [String: Any])?["KHR_animation_pointer"] as? [String: Any])?["pointer"] as? String
        })
        XCTAssertEqual(pointers, [
            "/materials/0/pbrMetallicRoughness/baseColorFactor", "/materials/0/pbrMetallicRoughness/roughnessFactor",
            "/materials/0/extensions/KHR_materials_emissive_strength/emissiveStrength",
            "/extensions/KHR_lights_punctual/lights/0/intensity", "/extensions/KHR_lights_punctual/lights/0/spot/outerConeAngle",
            "/extensions/KHR_lights_punctual/lights/0/spot/innerConeAngle", "/cameras/0/perspective/yfov"
        ])
        // The face state rides in the extras.
        let kept = ((file.json["extras"] as? [String: Any])?["maquette"] as? [String: Any])?["tracks"] as? [[String: Any]]
        XCTAssertEqual(kept?.count, 1)
    }

    /// Acceptance (X1 matrix: keys on any property ▸ glTF): every keyed number comes back with the same value at
    /// every moment.
    func testEveryKeyedNumberComesBack() throws {
        let scene = Self.keyedScene()
        var ids = IDFactory.sequential("in")
        let result = try GLTFSceneReader.read(GLTFScene.glb(nil, in: scene, look: Look()), ids: &ids)
        let names = Dictionary(uniqueKeysWithValues: result.fragment.objects.map { ($0.id, $0.name) })
        func back(_ name: String, _ property: PropertyKey) throws -> Track {
            try XCTUnwrap(result.tracks.first { names[$0.target] == name && $0.property == property }, "\(name) \(property)")
        }
        for (target, name) in [("lantern", "Lantern"), ("spot", "Spot"), ("cam", "Shot")] {
            for original in scene.timeline.tracks where original.target.raw == target {
                let copy = try back(name, original.property)
                XCTAssertEqual(copy.keyframes.count, original.keyframes.count, "\(original.property)")
                for time in stride(from: 0.0, through: 2, by: 0.25) {
                    try Self.assertSame(original.value(at: time), copy.value(at: time), "\(original.property) at \(time)")
                }
            }
        }
        // A held key stays held.
        XCTAssertEqual(try back("Spot", .lightIntensity).keyframes.first?.easing, .step)
        // The static glow under the keyed strength is the colour itself.
        let lantern = try XCTUnwrap(result.fragment.objects.first { $0.name == "Lantern" })
        XCTAssertEqual(lantern.emissiveIntensity, 0.5, accuracy: 1e-5)
    }

    func testAGlowBrighterThanWhiteKeepsItsStrength() throws {
        var lamp = SceneObject(id: "lamp", name: "Neon", kind: .primitive(.sphere))
        lamp[.emissive] = .color(.rgba(RGBA(1, 0.2, 0.6)))
        lamp[.emissiveIntensity] = .float(4)
        let scene = Scene(id: "s", name: "Sign", objects: ["lamp": lamp], roots: ["lamp"])
        var ids = IDFactory.sequential("in")
        let result = try GLTFSceneReader.read(GLTFScene.glb(nil, in: scene, look: Look()), ids: &ids)
        XCTAssertEqual(result.fragment.objects.first?.emissiveIntensity ?? 0, 4, accuracy: 1e-5)
    }

    func testTheLooksLacquerIsAClearcoat() throws {
        let file = try GLTFReader.parse(GLTFScene.glb(nil, in: Self.keyedScene(), look: Look(), clearcoat: 0.6), baseURL: nil)
        let coat = (file.array("materials").first?["extensions"] as? [String: Any])?["KHR_materials_clearcoat"] as? [String: Any]
        XCTAssertEqual(coat?["clearcoatFactor"] as? Double, 0.6)
        XCTAssertTrue((file.json["extensionsUsed"] as? [String] ?? []).contains("KHR_materials_clearcoat"))
    }

    static func assertSame(_ a: PropertyValue?, _ b: PropertyValue?, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        switch (a, b) {
        case let (.float(x), .float(y)):
            XCTAssertEqual(x, y, accuracy: 1e-3, message, file: file, line: line)
        case let (.color(x), .color(y)):
            let (p, q) = (x.resolved(in: .empty), y.resolved(in: .empty))
            for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b)] {
                XCTAssertEqual(u, v, accuracy: 1.0 / 255, message, file: file, line: line)
            }
        default:
            XCTAssertEqual(a, b, message, file: file, line: line)
        }
    }
}
