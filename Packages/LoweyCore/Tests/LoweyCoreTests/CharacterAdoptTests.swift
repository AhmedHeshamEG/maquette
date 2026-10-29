@testable import LoweyCore
import XCTest

/// Q2 step 2: the person's own model becomes the character, whole, where it stands, and keeps its own rig.
final class CharacterAdoptTests: XCTestCase {
    /// A cube with a rig of its own (weights in a skin file), as "Rig as a person" leaves it.
    private func robot() throws -> (Document, ObjectID, ObjectRig) {
        var ids = IDFactory.sequential("a")
        let cube = SceneObject(id: ids.next(), name: "Robot", kind: .primitive(.cube), transform: Transform(position: Vec3(2, 0, -1)))
        var rig = RigMarks.rig([RigMark(name: "hips", kind: .dot, position: Vec3(0, 0.3, 0)),
                                RigMark(name: "head", kind: .dot, position: Vec3(0, 0.8, 0), parent: "hips")], surface: [])
        rig.skin = "robot-weights"
        let document = try assertReverts(.batch("Robot", [.insert(SceneFragment(object: cube), parent: nil, index: nil), .setRig(cube.id, rig)]),
                                         on: makeDocument())
        return (document, cube.id, rig)
    }

    func testTheModelItselfBecomesTheCharacter() throws {
        let (document, robot, rig) = try robot()
        let adopted = try assertReverts(XCTUnwrap(CharacterMaker.adopt(robot, in: document.scene)), on: document)
        let object = try XCTUnwrap(adopted.scene.objects[robot])
        XCTAssertNotNil(object[.characterStart], "it is a character")
        XCTAssertEqual(object.part?.job, .body, "its own body")
        XCTAssertNil(object.parent, "no new group around it")
        XCTAssertEqual(adopted.scene.roots, document.scene.roots, "nothing new in the scene")
        XCTAssertEqual(adopted.scene.worldTransform(of: robot).position, Vec3(2, 0, -1), "it stays where it was")
        XCTAssertEqual(object.rig, rig, "its rig is untouched")
        XCTAssertEqual(CharacterMaker.character(of: robot, in: adopted.scene), robot)
        XCTAssertNil(CharacterMaker.adopt(robot, in: adopted.scene), "a character can't be made one again")
        XCTAssertEqual(CharacterAnatomy(robot, in: adopted.scene)?.body?.id, robot, "the maker reads it as its own body")
    }

    func testPartsRideItsOwnRigAndTheMakerNeverRebuildsIt() throws {
        let (document, robot, rig) = try robot()
        let adopted = try assertReverts(XCTUnwrap(CharacterMaker.adopt(robot, in: document.scene)), on: document)
        var ids = IDFactory.sequential("e")
        let eyes = try XCTUnwrap(CharacterMaker.add(.eye, to: robot, in: adopted.scene, ids: &ids))
        XCTAssertEqual(eyes.root, robot, "the eyes go on the model, not on a new character")
        let seeing = try assertReverts(CharacterAutoRig.rigging(after: eyes.command, root: robot, in: adopted, label: "Add eye"), on: adopted)
        XCTAssertEqual(seeing.scene.objects[robot]?.rig, rig, "its own rig is kept")
        for eye in eyes.made {
            XCTAssertEqual(seeing.scene.objects[eye]?.parent, robot)
            XCTAssertNotNil(seeing.scene.objects[eye]?[.attachBone], "each eye rides one of its joints")
        }
        let anatomy = try XCTUnwrap(CharacterAnatomy(robot, in: seeing.scene))
        XCTAssertTrue(CharacterProportions.bodyHeight(anatomy, factor: 1.2, scene: seeing.scene).isEmpty,
                      "its own body changes by hand, not by the maker's handles")
    }

    func testAPartOfACharacterIsNotMadeOneAgain() throws {
        var ids = IDFactory.sequential("p")
        let fragment = CharacterMaker.start(.person, name: "Person", at: .zero, ids: &ids)
        let document = try assertReverts(.insert(fragment, parent: nil, index: nil), on: makeDocument())
        let head = try XCTUnwrap(document.scene.subtree(of: fragment.roots[0]).first { document.scene.objects[$0]?.part?.job == .head })
        XCTAssertNil(CharacterMaker.adopt(head, in: document.scene))
        XCTAssertNil(CharacterMaker.adopt(fragment.roots[0], in: document.scene))
    }

    func testTheBridgeAdoptsAThing() throws {
        let (document, robot, _) = try robot()
        var context = ScriptContext(ids: .sequential("b"))
        context.mesh = { _ in nil }
        let actions = """
        {"do": "character", "op": "adopt", "target": "Robot"},
         {"do": "character", "op": "add", "target": "Robot", "part": "mouth"},
         {"do": "character", "op": "rig", "target": "Robot"}
        """
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        let result = try ScriptCompiler.compile(script, document: document, context: context)
        let applied = try assertReverts(XCTUnwrap(result.command), on: document)
        XCTAssertNotNil(applied.scene.objects[robot]?[.characterStart])
        XCTAssertTrue(applied.scene.objects[robot]?.children.contains { applied.scene.objects[$0]?.part?.job == .mouth } ?? false)
    }
}
