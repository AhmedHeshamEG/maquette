import Foundation

// MARK: - Review notes (U8)

extension ScriptState {
    /// `{"do": "note", "op": "add" | "list" | "reply" | "resolve" | "reopen" | "delete", …}`: the review pins.
    mutating func note(_ action: JSONValue) throws {
        switch string(action, "op") ?? "add" {
        case "add": try addNote(action)
        case "list": listNotes()
        case "reply":
            let id = try noteID(action)
            guard let text = string(action, "text") else { throw fail("reply needs “text”") }
            let replyID = (context.ids.next() as ObjectID).raw
            try run(ReviewNotes.reply(to: id, text, by: author(action), in: scene, replyID: replyID), label: "Reply")
        case "resolve": try run(ReviewNotes.setResolved(noteID(action), true, in: scene), label: "Resolve note")
        case "reopen": try run(ReviewNotes.setResolved(noteID(action), false, in: scene), label: "Reopen note")
        case "delete": try run(ReviewNotes.delete(noteID(action), in: scene), label: "Delete note")
        case let other: throw fail("note has no op “\(other)” (add, list, reply, resolve, reopen, delete)")
        }
    }

    /// `{"op": "add", "on": "Chair", "at": [x, y, z], "text": "Taller back?"}`: on a thing (at its top middle unless
    /// "at" says where), or at a point in the world.
    private mutating func addNote(_ action: JSONValue) throws {
        guard let text = string(action, "text"), !text.isEmpty else { throw fail("note needs “text”") }
        let thing = try action["on"].map { try target($0) }
        var place = try point(action["at"])
        if place == nil, let thing {
            let box = SceneBounds(library: context.library).worldBounds(of: thing, in: scene)
            place = box.map { Vec3($0.center.x, $0.max.y, $0.center.z) } ?? scene.worldTransform(of: thing).position
        }
        guard let place else { throw fail("note needs “on” (a thing) or “at” (a point)") }
        let (command, note) = ReviewNotes.add(text, by: author(action), at: place, on: thing, time: number(action, "time"), in: scene,
                                              id: (context.ids.next() as ObjectID).raw)
        try run(command, label: "Note \(scene.notes.count + 1): \(note.text)")
    }

    private mutating func listNotes() {
        guard !scene.notes.isEmpty else {
            report.append("No notes")
            return
        }
        for (index, note) in scene.notes.enumerated() {
            let thing = note.object.flatMap { scene.objects[$0]?.name } ?? "the scene"
            let replies = note.replies.map { "\($0.author): \($0.text)" }.joined(separator: " / ")
            report.append("\(index + 1) [\(note.id)] on \(thing), \(note.resolved ? "resolved" : "open") · \(note.author): \(note.text)"
                + (replies.isEmpty ? "" : " — \(replies)"))
        }
    }

    /// A note by its id or its number in the list (from 1).
    private func noteID(_ action: JSONValue) throws -> String {
        if let number = number(action, "note"), let index = Int(exactly: number), scene.notes.indices.contains(index - 1) {
            return scene.notes[index - 1].id
        }
        if let id = string(action, "note"), scene.note(id) != nil { return id }
        throw fail("no such note (give “note”: its id or its number; there are \(scene.notes.count))")
    }

    private func author(_ action: JSONValue) -> String {
        string(action, "author") ?? "Assistant"
    }
}
