@testable import LoweyCore
import XCTest

/// K1's game outputs: an engine-ready character (skeleton named for the engine, blend shapes, named clips, LODs, a
/// capsule) and sprite sheets from 4 or 8 directions. `ACCEPTANCE_DIR` writes them for the Godot checks on CI.
final class CharacterGameTests: XCTestCase {
    /// A made character, rigged by itself.
    static func made(_ start: CharacterStart, name: String) throws -> (Document, ObjectID) {
        var ids = IDFactory.sequential(name)
        let fragment = CharacterMaker.start(start, name: name, at: .zero, ids: &ids)
        var document = makeDocument()
        _ = try EditCommand.insert(fragment, parent: nil, index: nil).apply(to: &document)
        let root = fragment.roots[0]
        let anatomy = try XCTUnwrap(CharacterAnatomy(root, in: document.scene))
        let rig = CharacterAutoRig.rig(CharacterAutoRig.marks(anatomy))
        _ = try EditCommand.setRig(root, rig).apply(to: &document)
        _ = try EditCommand.setProperties(RigidParts.binding(root, rig: rig, in: document.scene)).apply(to: &document)
        return (document, root)
    }

    private func write(_ data: Data, _ folder: String, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try data.write(to: url.appendingPathComponent(name))
    }

    func testAPersonLeavesEngineReady() throws {
        var (document, root) = try Self.made(.person, name: "Hero")
        var ids = IDFactory.sequential("l")
        let line = try XCTUnwrap(LipSync.line("Ready to go!", character: root, from: 0, language: "en-US", timeline: document.scene.timeline, ids: &ids))
        _ = try line.apply(to: &document)
        let glb = try XCTUnwrap(GameCharacterExport.glb(root, document: document, options: .init(engine: .godot)))
        let json = try PhysicsExportTests.glbJSON(glb)
        let nodes = try XCTUnwrap(json["nodes"] as? [[String: Any]])
        let names = Set(nodes.compactMap { $0["name"] as? String })
        for bone in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperLeg", "RightLowerLeg", "RightFoot"] {
            XCTAssertTrue(names.contains(bone), "Godot's humanoid profile reads \(bone)")
        }
        XCTAssertTrue(names.contains("Hero_LOD0") && names.contains("Hero_LOD1") && names.contains("Hero_LOD2"))
        XCTAssertTrue(names.contains("Hero_collider"))
        let skins = try XCTUnwrap(json["skins"] as? [[String: Any]])
        XCTAssertEqual(skins.count, 1)
        let animations = try XCTUnwrap(json["animations"] as? [[String: Any]]).compactMap { $0["name"] as? String }
        XCTAssertTrue(Set(BuiltinClips.names).isSubset(of: Set(animations)), "the ten humanoid clips, by name")
        XCTAssertTrue(animations.contains("Timeline"), "its own lip sync")
        let meshes = try XCTUnwrap(json["meshes"] as? [[String: Any]])
        let mouth = try XCTUnwrap(meshes.first { ($0["name"] as? String) == "Mouth" })
        XCTAssertEqual((mouth["extras"] as? [String: Any])?["targetNames"] as? [String], Array(FaceStates.names(for: .mouth).dropFirst()),
                       "the 13 mouth shapes past neutral are blend shapes")
        let shapes = (json["extensions"] as? [String: Any])?["OMI_physics_shape"] as? [String: Any]
        XCTAssertEqual(((shapes?["shapes"] as? [[String: Any]])?.first)?["type"] as? String, "capsule")
        try write(glb, "characters", "person.glb")
        // Unreal: the mannequin's names, from a root bone on the ground.
        let unreal = try PhysicsExportTests.glbJSON(XCTUnwrap(GameCharacterExport.glb(root, document: document, options: .init(engine: .unreal))))
        let unrealNames = Set((unreal["nodes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        XCTAssertTrue(["root", "pelvis", "spine_01", "upperarm_l", "calf_r", "ball_l"].allSatisfy(unrealNames.contains))
    }

    func testSpriteSheetsPackEveryDirection() throws {
        let (document, root) = try Self.made(.fourLegs, name: "Dog")
        var strips: [SpriteSheet.Strip] = []
        for direction in SpriteSheet.Direction.four {
            let frames = (0 ..< 6).map { frame in
                FlatRaster.picture(of: root, in: Animator.evaluate(document, at: Double(frame) / 12).scene, yaw: direction.yaw, size: 48)
            }
            strips.append(SpriteSheet.Strip(clip: "Idle", direction: direction, frames: frames, fps: 12))
        }
        let packed = try XCTUnwrap(SpriteSheet.pack(strips, imageName: "dog.png"))
        XCTAssertEqual(packed.image.height, 48 * 4)
        XCTAssertEqual(packed.image.width, 48 * 6)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: packed.json) as? [String: Any])
        XCTAssertEqual((json["frames"] as? [String: Any])?.count, 24)
        let tags = try XCTUnwrap((json["meta"] as? [String: Any])?["frameTags"] as? [[String: Any]])
        XCTAssertEqual(tags.map { $0["name"] as? String }, ["idle_S", "idle_E", "idle_N", "idle_W"])
        XCTAssertTrue(packed.spriteFrames.contains("&\"idle_N\""))
        XCTAssertTrue(packed.image.pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element == 255 }, "the dog is drawn")
        let pixel = PixelArt.render(strips[0].frames[0], settings: PixelArt.Settings(height: 24, colours: 6))
        XCTAssertEqual(pixel.height, 26, "24 pixels and the outline")
        XCTAssertTrue(pixel.pixels.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 0 || $0.element == 255 }, "no soft edges")
        let turnaround = try XCTUnwrap(SpriteSheet.turnaround(strips.map { $0.frames[0] }))
        XCTAssertGreaterThan(turnaround.width, 48 * 4)
        try write(PNGCodec.encode(packed.image), "sprites", "dog.png")
        try write(packed.json, "sprites", "dog.json")
        try write(Data(packed.spriteFrames.utf8), "sprites", "dog.tres")
    }
}

/// A tiny depth-tested, flat-shaded rasteriser for the tests' sprite frames (the app renders frames with the stage's
/// renderer; this only gives the packer real pictures to pack).
enum FlatRaster {
    static func picture(of root: ObjectID, in scene: Scene, yaw: Double, size: Int) -> RGBAImage {
        var image = RGBAImage(width: size, height: size, color: RGBA(0, 0, 0, 0))
        var depth = [Double](repeating: -.infinity, count: size * size)
        // East faces the right of the picture: the character turns, the camera stays.
        let turn = Quat(angle: yaw * .pi / 180, axis: .unitY)
        let scale = Double(size) / 1.4
        for id in scene.subtree(of: root) {
            guard let object = scene.objects[id], object.isVisible, let mesh = SceneExport.localMesh(of: object, look: Look()) else { continue }
            let world = scene.worldTransform(of: id)
            let colour = object.color?.resolved(in: .empty) ?? .white
            let points = mesh.positions.map { turn.act(world.apply(to: Vec3($0))) }
            for tri in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let a = points[Int(mesh.indices[tri])], b = points[Int(mesh.indices[tri + 1])], c = points[Int(mesh.indices[tri + 2])]
                let normal = (b - a).cross(c - a).normalized
                let light = 0.55 + 0.45 * max(normal.dot(Vec3(0.3, 0.8, 0.5).normalized), 0)
                fill(a, b, c, colour: colour.scaled(light), scale: scale, size: size, image: &image, depth: &depth)
            }
        }
        return image
    }

    static func fill(_ a: Vec3, _ b: Vec3, _ c: Vec3, colour: RGBA, scale: Double, size: Int, image: inout RGBAImage, depth: inout [Double]) {
        func screen(_ p: Vec3) -> (Double, Double) { (p.x * scale + Double(size) / 2, Double(size) - 2 - p.y * scale) }
        let (ax, ay) = screen(a), (bx, by) = screen(b), (cx, cy) = screen(c)
        let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        guard abs(area) > 1e-9 else { return }
        let minX = max(Int(min(ax, bx, cx)), 0), maxX = min(Int(max(ax, bx, cx)) + 1, size - 1)
        let minY = max(Int(min(ay, by, cy)), 0), maxY = min(Int(max(ay, by, cy)) + 1, size - 1)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY ... maxY {
            for x in minX ... maxX {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
                let w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
                let w2 = 1 - w0 - w1
                guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
                let z = w0 * a.z + w1 * b.z + w2 * c.z
                guard z > depth[y * size + x] else { continue }
                depth[y * size + x] = z
                image.setPixel(x, y, colour)
            }
        }
    }
}
