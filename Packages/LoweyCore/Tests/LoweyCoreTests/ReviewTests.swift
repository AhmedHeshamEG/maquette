import Foundation
@testable import LoweyCore
import XCTest

/// U8: review notes stuck on spots and answered in place, the bridge's `note`, the messages between devices, and the
/// film's shots for presenting.
final class ReviewTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func document(chairAt position: Vec3 = Vec3(2, 0, 0)) -> Document {
        var scene = Scene(id: "s", name: "S")
        scene.objects["chair"] = SceneObject(id: "chair", name: "Chair", kind: .primitive(.cube), transform: Transform(position: position))
        scene.roots = ["chair"]
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    func testANoteRidesOnItsThing() throws {
        var session = EditSession(document: document())
        let (command, note) = ReviewNotes.add("Taller back?", by: "Sara", at: Vec3(2, 1, 0), on: "chair", in: session.document.scene,
                                              id: "n1", date: date)
        try session.perform(command)
        XCTAssertEqual(note.point, Vec3(0, 1, 0), "kept in the chair's own space")
        try session.perform(.setProperties([PropertyChange(object: "chair", key: .position, value: .vec3(Vec3(5, 0, 0)))]))
        let moved = try XCTUnwrap(session.document.scene.note("n1"))
        XCTAssertEqual(moved.position(in: session.document.scene), Vec3(5, 1, 0), "the note follows the chair")
        try session.perform(.delete(["chair"]))
        XCTAssertEqual(session.document.scene.note("n1")?.position(in: session.document.scene), Vec3(2, 1, 0),
                       "with its thing gone, it stays where it was written")
    }

    func testAThreadIsAnsweredResolvedAndUndone() throws {
        var session = EditSession(document: document())
        try session.perform(ReviewNotes.add("Taller back?", by: "Sara", at: Vec3(2, 1, 0), on: "chair", in: session.document.scene,
                                            id: "n1", date: date).0)
        try session.perform(XCTUnwrap(ReviewNotes.setResolved("n1", true, in: session.document.scene)))
        try session.perform(XCTUnwrap(ReviewNotes.reply(to: "n1", "Done, 10 cm", by: "Hesham", in: session.document.scene, replyID: "r1",
                                                        date: date)))
        var note = try XCTUnwrap(session.document.scene.note("n1"))
        XCTAssertEqual(note.replies.map(\.text), ["Done, 10 cm"])
        XCTAssertFalse(note.resolved, "an answer opens it again")
        XCTAssertEqual(note.people, ["Sara", "Hesham"])
        XCTAssertNil(ReviewNotes.reply(to: "n1", "   ", by: "Hesham", in: session.document.scene), "an empty answer isn't one")
        try session.undo()
        note = try XCTUnwrap(session.document.scene.note("n1"))
        XCTAssertTrue(note.replies.isEmpty)
        XCTAssertTrue(note.resolved)
        try session.perform(XCTUnwrap(ReviewNotes.delete("n1", in: session.document.scene)))
        XCTAssertTrue(session.document.scene.notes.isEmpty)
        try session.undo()
        XCTAssertEqual(session.document.scene.notes.map(\.id), ["n1"])
    }

    func testClearingResolvedNotesKeepsTheOpenOnes() throws {
        var session = EditSession(document: document())
        for (id, text) in [("a", "One"), ("b", "Two"), ("c", "Three")] {
            try session.perform(ReviewNotes.add(text, by: "Omar", at: .zero, on: nil, in: session.document.scene, id: id, date: date).0)
        }
        try session.perform(XCTUnwrap(ReviewNotes.setResolved("b", true, in: session.document.scene)))
        try session.perform(XCTUnwrap(ReviewNotes.clearResolved(in: session.document.scene)))
        XCTAssertEqual(session.document.scene.notes.map(\.id), ["a", "c"])
        XCTAssertEqual(session.document.scene.openNotes.count, 2)
        XCTAssertNil(ReviewNotes.clearResolved(in: session.document.scene))
    }

    func testNotesTravelInTheFileAndTheJournal() throws {
        var scene = document().scene
        scene.notes = [ReviewNote(id: "n1", object: "chair", point: Vec3(0, 1, 0), world: Vec3(2, 1, 0), author: "Sara", text: "Hi",
                                  date: date, time: 2, replies: [ReviewReply(id: "r", author: "H", text: "Yes", date: date)], resolved: true)]
        let data = try SchemaCoder.shared.encode(scene, kind: .scene)
        XCTAssertEqual(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data).notes, scene.notes)
        let command = EditCommand.setNotes([NoteEdit(scene.notes[0])])
        XCTAssertEqual(try JSONDecoder().decode(EditCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertEqual(command.label, "Note")
        XCTAssertEqual(EditCommand.setNotes([NoteEdit(id: "n1", note: nil)]).label, "Delete note")
        // A scene with no notes writes none (files from before stay as they were).
        let empty = try SchemaCoder.shared.encode(Scene(id: "e", name: "E"), kind: .scene)
        XCTAssertFalse(String(decoding: empty, as: UTF8.self).contains("notes"))
    }

    func testA23FileOpens() throws {
        let old = """
        {"schemaVersion": 23, "kind": "scene", "payload": {"id": "s", "name": "Old", "objects": {}, "roots": [],
         "viewpoint": {"target": [0, 0.5, 0], "yaw": 35, "pitch": 28, "distance": 9, "projection": "perspective", "fieldOfView": 50},
         "timeline": {"fps": 30, "duration": 10, "stepping": 1, "tracks": []}}}
        """
        XCTAssertTrue(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data(old.utf8)).notes.isEmpty)
    }

    func testTheBridgeWritesAndAnswersNotes() throws {
        let script = """
        {"version": 3, "title": "Review", "actions": [
          {"do": "note", "text": "Taller back?", "on": "Chair", "author": "Sara"},
          {"do": "note", "text": "Window here", "at": [0, 1.5, -3]},
          {"do": "note", "op": "reply", "note": 1, "text": "Done"},
          {"do": "note", "op": "resolve", "note": 2},
          {"do": "note", "op": "list"}
        ]}
        """
        let result = try ScriptCompiler.compile(LoweyJSON.decode(SceneScript.self, from: Data(script.utf8)), document: document(),
                                                context: ScriptContext(ids: .sequential("run")))
        let notes = result.document.scene.notes
        XCTAssertEqual(notes.map(\.text), ["Taller back?", "Window here"])
        XCTAssertEqual(notes[0].object, "chair")
        XCTAssertEqual(notes[0].author, "Sara")
        XCTAssertEqual(notes[0].replies.map(\.author), ["Assistant"])
        XCTAssertTrue(notes[1].resolved)
        XCTAssertNil(notes[1].object)
        XCTAssertTrue(result.report.contains { $0.hasPrefix("1 [") && $0.contains("Sara: Taller back?") && $0.contains("Assistant: Done") })
        let bad = """
        {"version": 3, "title": "Bad", "actions": [{"do": "note", "op": "reply", "note": 4, "text": "?"}]}
        """
        XCTAssertThrowsError(try ScriptCompiler.compile(LoweyJSON.decode(SceneScript.self, from: Data(bad.utf8)), document: document(),
                                                        context: ScriptContext(ids: .sequential("run"))))
    }

    func testMessagesBetweenDevicesSurviveTheTrip() throws {
        let pose = CompanionMessage.cameraPose(Transform(position: Vec3(0.1, 0, -0.2)))
        guard case let .cameraPose(back)? = try CompanionMessage.decode(pose.encoded()) else { return XCTFail("no pose") }
        XCTAssertEqual(back.position, Vec3(0.1, 0, -0.2))
        let walk = CompanionMessage.remote(.walk(moveX: 0, moveY: 1, lookX: -0.5, lookY: 0))
        guard case .remote(.walk(_, 1, -0.5, _))? = try CompanionMessage.decode(walk.encoded()) else { return XCTFail("no walk") }
        let model = CompanionMessage.model(name: "Tower", data: Data([1, 2, 3]))
        guard case let .model(name, data)? = try CompanionMessage.decode(model.encoded()) else { return XCTFail("no model") }
        XCTAssertEqual(name, "Tower")
        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertNil(CompanionMessage.decode(Data("nonsense".utf8)))
        let view = ReviewMessage.view(.default, from: "Sara", sequence: 4)
        guard case let .view(viewpoint, from, sequence)? = try ReviewMessage.decode(view.encoded()) else { return XCTFail("no view") }
        XCTAssertEqual(viewpoint, .default)
        XCTAssertEqual(from, "Sara")
        XCTAssertEqual(sequence, 4)
    }

    func testWhatAniPhoneCanDo() {
        let plain = CompanionAbilities(faceTracking: true, worldTracking: true)
        XCTAssertTrue(plain.can(.face))
        XCTAssertTrue(plain.can(.remote))
        XCTAssertFalse(plain.can(.roomScan), "a room scan needs LiDAR")
        XCTAssertTrue(CompanionAbilities().can(.remote), "any iPhone is a remote")
    }

    func testTheViewFollowsWhoeverMovedItLast() {
        var lead = ViewLead(quiet: 0.5)
        XCTAssertTrue(lead.accepts(from: "Sara", sequence: 1, at: 10))
        lead.movedHere(at: 10.2)
        XCTAssertFalse(lead.accepts(from: "Sara", sequence: 2, at: 10.4), "this person is turning it")
        XCTAssertTrue(lead.accepts(from: "Sara", sequence: 3, at: 10.8), "still for a moment: Sara leads again")
        XCTAssertFalse(lead.accepts(from: "Sara", sequence: 2, at: 11), "an older view arriving late is dropped")
        XCTAssertTrue(lead.accepts(from: "Omar", sequence: 1, at: 11), "each person counts their own")
    }

    func testPresentingStepsThroughTheShots() {
        var timeline = Timeline()
        timeline.duration = 12
        timeline.cuts = [CameraCut(time: 8, camera: "c"), CameraCut(time: 3, camera: "b"), CameraCut(time: 3, camera: "b2"),
                         CameraCut(time: 12, camera: "late")]
        let plan = PresentPlan(timeline)
        XCTAssertEqual(plan.shots.map(\.start), [0, 3, 8], "a free view before the first cut; two cuts at 3 s are one shot; none at the end")
        XCTAssertEqual(plan.shots[1].camera, "b2")
        XCTAssertEqual(plan.index(at: 5), 1)
        XCTAssertEqual(plan.next(after: 5), 8)
        XCTAssertNil(plan.next(after: 9))
        XCTAssertEqual(plan.previous(before: 5), 3, "back to this shot's start")
        XCTAssertEqual(plan.previous(before: 3.4), 0, "near its start: the shot before")
        XCTAssertEqual(plan.previous(before: 0.2), 0)
        var single = Timeline()
        single.cuts = [CameraCut(time: 0, camera: "a")]
        XCTAssertEqual(PresentPlan(single).shots.map(\.camera), ["a"])
    }
}
