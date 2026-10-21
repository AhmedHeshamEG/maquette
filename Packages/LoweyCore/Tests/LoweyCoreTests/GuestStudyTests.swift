@testable import LoweyCore
import XCTest

/// G1, Study: Omar's exploded view in one tap and his technical PDF (three views, sizes, a parts list).
final class GuestStudyTests: XCTestCase {
    /// A gearbox-like group: a base, two wheels side by side on it, a lid on top.
    static func assembly() throws -> Document {
        var document = Document(project: ProjectInfo(id: "p", name: "Gearbox"), scene: Scene(id: "s", name: "Gearbox"))
        var group = SceneObject(id: ObjectID(raw: "g"), name: "Gearbox", kind: .group)
        let parts: [(String, Vec3, PrimitiveShape)] = [("Base", Vec3(0, 0, 0), .cube), ("Wheel", Vec3(-0.6, 1, 0), .cylinder),
                                                        ("Wheel", Vec3(0.6, 1, 0), .cylinder), ("Lid", Vec3(0, 2, 0), .cube)]
        var objects: [SceneObject] = []
        for (index, (name, position, shape)) in parts.enumerated() {
            var object = SceneObject(id: ObjectID(raw: "p\(index)"), name: name, kind: .primitive(shape),
                                     transform: Transform(position: position, scale: Vec3(1, 1, 1)))
            object.parent = group.id
            if name == "Wheel" { object.physics = ObjectPhysics(material: .steel) }
            objects.append(object)
        }
        group.children = objects.map(\.id)
        _ = try EditCommand.insert(SceneFragment(objects: [group] + objects, roots: [group.id]), parent: nil, index: nil).apply(to: &document)
        return document
    }

    func testExplodeInOneTapPullsThePartsApartAndBack() throws {
        var document = try Self.assembly()
        let bounds = SceneBounds()
        let command = try XCTUnwrap(Explode.toggle(ObjectID(raw: "g"), in: document.scene) { bounds.worldBounds(of: $0, in: document.scene) })
        _ = try command.apply(to: &document)
        let exploded = Animator.evaluate(document, at: 0).scene
        let before = document.scene
        // The wheels move outward, away from each other; the lid moves up.
        XCTAssertLessThan(exploded.worldTransform(of: ObjectID(raw: "p1")).position.x, before.worldTransform(of: ObjectID(raw: "p1")).position.x)
        XCTAssertGreaterThan(exploded.worldTransform(of: ObjectID(raw: "p2")).position.x, before.worldTransform(of: ObjectID(raw: "p2")).position.x)
        XCTAssertGreaterThan(exploded.worldTransform(of: ObjectID(raw: "p3")).position.y, 2.5)
        // Tapped again, it goes back together.
        let back = try XCTUnwrap(Explode.toggle(ObjectID(raw: "g"), in: document.scene) { bounds.worldBounds(of: $0, in: document.scene) })
        _ = try back.apply(to: &document)
        let together = Animator.evaluate(document, at: 0).scene
        XCTAssertEqual(together.worldTransform(of: ObjectID(raw: "p3")).position.y, 2, accuracy: 1e-9)
        XCTAssertNil(Explode.toggle(ObjectID(raw: "p0"), in: document.scene) { _ in nil })
    }

    func testTheTechnicalSheetHasViewsSizesAndAPartsList() throws {
        let document = try Self.assembly()
        let look = Look()
        let things = document.scene.subtree(of: ObjectID(raw: "g")).compactMap { id -> (object: SceneObject, meshes: [ExportMesh])? in
            guard let object = document.scene.objects[id], object.kind.hasSurface else { return nil }
            return (object, SceneExport.meshes([id], in: document.scene, look: look))
        }
        let parts = TechnicalSheet.parts(things)
        XCTAssertEqual(parts.map(\.name), ["Base", "Wheel", "Lid"])
        XCTAssertEqual(parts[1].count, 2)
        XCTAssertEqual(parts[1].material, "Steel")
        XCTAssertEqual(parts[0].material, "Plastic")
        // A unit cube of plastic weighs 950 kg.
        XCTAssertEqual(try XCTUnwrap(parts[0].mass), 950, accuracy: 1)
        let soup = TriangleSoup(things.flatMap(\.meshes))
        let pdf = TechnicalSheet.pdf(assembly: soup, parts: parts, sheet: TechnicalSheet.Sheet(title: "Gearbox", author: "Omar",
                                                                                             date: Date(timeIntervalSince1970: 0), units: .metre))
        let text = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("%PDF"))
        for words in ["Gearbox", "Omar", "First angle", "Steel", "Plastic", "Mass", "1970-01-01", "1:"] {
            XCTAssertTrue(text.contains(words), words)
        }
        // Hidden edges are dashed.
        XCTAssertTrue(text.contains("] 0 d") && text.contains("[5.669"))
        XCTAssertEqual(TechnicalSheet.massText(0.0123), "12.3 g")
        XCTAssertEqual(TechnicalSheet.massText(1.25), "1.25 kg")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("study")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try pdf.write(to: folder.appendingPathComponent("gearbox.pdf"))
        }
    }
}
