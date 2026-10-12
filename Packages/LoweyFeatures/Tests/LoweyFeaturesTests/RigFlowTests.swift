import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// Rig in the editor (U4): pins and dots rig an object in one undo step (its weights written to the project first, a
/// shape too coarse to bend cut finer in the same step), a changed rig keeps the pose of the joints that stay, a group
/// rigs rigid, joints turned in Keys are keyed like any property, and removing the rig takes its pose and keys with it.
@MainActor
final class RigFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Rig \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    /// Waits until the object's rig is no longer `old` (the background weighing landed).
    private func waitForRig(on id: ObjectID, in editor: EditorModel, changedFrom old: ObjectRig? = nil, file: StaticString = #filePath,
                            line: UInt = #line) async throws -> ObjectRig {
        // Bone heat on CI's simulator takes several seconds.
        for _ in 0 ..< 900 where editor.baseScene.objects[id]?.rig == old || editor.rigging.weighing[id] != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(editor.baseScene.objects[id]?.rig, "the rig arrived", file: file, line: line)
    }

    /// Three dots up the middle of a unit cube (rig space): its base, its middle, its top.
    private func dots() -> [RigMark] {
        [RigMark(name: "j1", kind: .dot, position: Vec3(0, 0.1, 0), thickness: 1),
         RigMark(name: "j2", kind: .dot, position: Vec3(0, 0.5, 0), parent: "j1", thickness: 1),
         RigMark(name: "j3", kind: .dot, position: Vec3(0, 0.9, 0), parent: "j2", thickness: 1)]
    }

    func testDotsRigACubeInOneStepAndCutItFiner() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        XCTAssertNil(editor.rigBlocker(cube))
        editor.startMarking(cube.id)
        XCTAssertEqual(editor.tool, .rig)
        XCTAssertEqual(editor.rigging.mode, .marks)
        editor.storeMarks(dots(), on: cube, label: "Rig Cube")
        let rig = try await waitForRig(on: cube.id, in: editor)
        XCTAssertEqual(rig.marks.map(\.name), ["j1", "j2", "j3"], "the marks travel with the rig")
        XCTAssertNotNil(try editor.paintFiles(XCTUnwrap(rig.skin)), "the weights are in the project")
        let rigged = try XCTUnwrap(editor.baseScene.objects[cube.id])
        XCTAssertNotNil(rigged[.bendDetail], "eight corners can't bend: the cube was cut finer")
        XCTAssertTrue(editor.rigFits(rigged))
        XCTAssertEqual(editor.shownMarks(of: rigged).count, 3)
        XCTAssertEqual(editor.castType(of: cube.id), .drawn, "a rigged object joins the cast")
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[cube.id]?.rig, "one undo step")
        XCTAssertNil(editor.baseScene.objects[cube.id]?[.bendDetail], "the cut goes with it")
    }

    func testAChangedRigKeepsThePoseOfTheJointsThatStay() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        editor.storeMarks(dots(), on: cube, label: "Rig Cube")
        let first = try await waitForRig(on: cube.id, in: editor)
        editor.setProperty(.boneTurn("j2"), .quat(Quat(angle: 0.4, axis: .unitZ)))
        editor.setProperty(.boneTurn("j3"), .quat(Quat(angle: 0.2, axis: .unitZ)))
        // Move the middle dot up and take the top one away.
        var marks = RigMarks.moving("j2", to: Vec3(0, 0.6, 0), in: first.marks)
        marks = RigMarks.removing("j3", from: marks)
        try editor.storeMarks(marks, on: XCTUnwrap(editor.baseScene.objects[cube.id]), label: "Change the rig")
        let second = try await waitForRig(on: cube.id, in: editor, changedFrom: first)
        XCTAssertEqual(second.skeleton.names, ["j1", "j2"])
        XCTAssertNotNil(editor.baseScene.objects[cube.id]?[.boneTurn("j2")], "the moved joint keeps its turn")
        XCTAssertNil(editor.baseScene.objects[cube.id]?[.boneTurn("j3")], "the removed joint's turn went with it")
        editor.undo()
        XCTAssertEqual(editor.baseScene.objects[cube.id]?.rig, first, "one undo step")
        XCTAssertNotNil(editor.baseScene.objects[cube.id]?[.boneTurn("j3")])
    }

    func testAGroupRigsRigidAndItsPartsRideTheirBones() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let lower = try XCTUnwrap(editor.singleSelection)
        editor.addPrimitive(.cube)
        let upper = try XCTUnwrap(editor.singleSelection)
        editor.setSelection([lower.id, upper.id])
        editor.rigTogether()
        let group = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(editor.tool, .rig)
        let marks = [RigMark(name: RigMarks.rootName, kind: .dot, position: .zero),
                     RigMark(name: "j2", kind: .dot, position: Vec3(0, 1, 0), parent: RigMarks.rootName)]
        editor.storeMarks(marks, on: group, label: "Rig Group")
        // No skin to work out: the parts are bound at once.
        XCTAssertNotNil(editor.baseScene.objects[group.id]?.rig)
        let bound = [lower.id, upper.id].compactMap { editor.baseScene.objects[$0]?[.attachBone]?.stringValue }
        XCTAssertEqual(bound.count, 2, "every part rides a bone")
        editor.removeRig(group.id)
        XCTAssertNil(editor.baseScene.objects[lower.id]?[.attachBone], "removing the rig lets the parts go")
    }

    func testJointsTurnedInKeysAreKeyedAndGoWithTheRig() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        editor.storeMarks(dots(), on: cube, label: "Rig Cube")
        let rig = try await waitForRig(on: cube.id, in: editor)
        editor.tool = .select
        let character = try XCTUnwrap(CharacterRig.of(cube.id, in: editor.baseScene))
        editor.timelineMode = .keyframe
        editor.setSelection([cube.id])
        editor.keySelection()
        editor.setTime(1)
        let joint = try XCTUnwrap(rig.skeleton.index(of: "j2"))
        _ = editor.perform(.setProperties(character.changes(turning: [joint: Quat(angle: 0.5, axis: .unitZ)])))
        let key = PropertyKey.boneTurn("j2")
        XCTAssertNotNil(editor.timeline.track(for: cube.id, key), "a bone turn is keyed at the playhead")
        let handles = IKHandles.handles(of: cube.id, in: editor.displayed.scene)
        XCTAssertEqual(Set(handles.map(\.name)), ["j2", "j3"], "the dots below the first are handles")
        editor.removeRig(cube.id)
        XCTAssertNil(editor.baseScene.objects[cube.id]?.rig)
        XCTAssertNil(editor.timeline.track(for: cube.id, key), "its keys go with it")
        XCTAssertFalse(editor.baseScene.objects[cube.id]?.properties.keys.contains { $0.boneJoint != nil } ?? true)
    }

    func testAMotionSavedToTheLibraryDropsOnAnotherThing() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let first = try XCTUnwrap(editor.singleSelection)
        editor.storeMarks(dots(), on: first, label: "Rig Cube")
        _ = try await waitForRig(on: first.id, in: editor)
        let pose = CharacterPose(id: "p", name: "Bent", joints: ["j2": Quat(angle: 0.6, axis: .unitZ), "tail": Quat(angle: 0.1, axis: .unitX)])
        let before = editor.library.manifest.motions.count
        editor.savePoseToLibrary(pose, of: first.id)
        let saved = try XCTUnwrap(editor.library.manifest.motions.last)
        XCTAssertEqual(editor.library.manifest.motions.count, before + 1)
        editor.setSelection([first.id])
        editor.applyMotion(saved)
        XCTAssertNotNil(editor.baseScene.objects[first.id]?[.boneTurn("j2")], "it played where the joints match")
        editor.library.removeMotion(saved.id)
    }

    func testRiggingIsRefusedWhereItCantWork() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.plane)
        let plane = try XCTUnwrap(editor.singleSelection)
        XCTAssertNotNil(editor.rigBlocker(plane))
        editor.startMarking(plane.id)
        XCTAssertNotEqual(editor.tool, .rig)
    }
}
