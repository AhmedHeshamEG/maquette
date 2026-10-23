import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import UIKit

/// Review notes (U8): a note stuck on a spot, carried in the file and answered in place. Actions ▸ Notes shows the
/// pins; Add a note, then a tap on the spot; a pin's tap opens its thread beside it. In a review over FaceTime every
/// note written, answered or resolved reaches the others at once.
extension EditorModel {
    /// The name notes are signed with (Settings ▸ Your layout ▸ Your name, else this iPad's).
    var yourName: String { YourSettings.name(device: UIDevice.current.name) }

    func setNotesShown(_ shown: Bool) {
        together.notesShown = shown
        if !shown {
            together.placingNote = false
            together.draft = nil
            together.openNote = nil
        }
        viewRevision &+= 1
    }

    /// Add a note: the next tap on the stage says where.
    func beginNote() {
        openPanel = nil
        setNotesShown(true)
        together.openNote = nil
        together.placingNote = true
        HmmHaptics.play(.selection)
        app.show("Tap where the note goes")
    }

    /// The tap after Add a note: on a thing (the note rides on it) or on the ground. True when it was taken.
    func placeNote(at point: CGPoint, picked: (ObjectID, SurfaceHit)?) -> Bool {
        guard together.placingNote else { return false }
        together.placingNote = false
        let world = picked?.1.point ?? stage?.groundPoint(at: point)
        guard let world else { return true }
        together.draft = NoteDraft(world: world, object: picked?.0)
        HmmHaptics.play(.selection)
        return true
    }

    /// The draft's words become a note (empty: the draft goes).
    func commitNote() {
        guard let draft = together.draft else { return }
        together.draft = nil
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let (command, note) = ReviewNotes.add(text, by: yourName, at: draft.world, on: draft.object, time: directorView ? time : nil,
                                              in: baseScene)
        performNotes(command)
        together.openNote = note.id
    }

    func replyToNote(_ id: String, _ text: String) {
        performNotes(ReviewNotes.reply(to: id, text, by: yourName, in: baseScene))
    }

    func setNoteResolved(_ id: String, _ resolved: Bool) {
        performNotes(ReviewNotes.setResolved(id, resolved, in: baseScene))
        if resolved, together.openNote == id { together.openNote = nil }
    }

    func deleteNote(_ id: String) {
        performNotes(ReviewNotes.delete(id, in: baseScene))
        if together.openNote == id { together.openNote = nil }
    }

    func clearResolvedNotes() {
        performNotes(ReviewNotes.clearResolved(in: baseScene))
    }

    /// Opens a note's thread (and, for a note on a shot, goes to its moment).
    func openNote(_ id: String) {
        together.openNote = together.openNote == id ? nil : id
        if let time = baseScene.note(id)?.time, together.openNote == id { setTime(time, snap: false) }
        HmmHaptics.play(.selection)
    }

    /// Performs a note change and tells the others in a review.
    private func performNotes(_ command: EditCommand?) {
        guard let command, perform(command) else { return }
        if case let .batch(_, steps) = command, case let .setNotes(edits)? = steps.first {
            app.review.send(.notes(edits))
        }
        viewRevision &+= 1
    }

    /// Notes from someone else in the review.
    func receiveNotes(_ edits: [NoteEdit]) {
        _ = perform(.batch(edits.allSatisfy { $0.note == nil } ? "Delete note" : "Note", [.setNotes(edits)]))
        if !together.notesShown { setNotesShown(true) }
        viewRevision &+= 1
    }

    /// Where each pin is on screen now (only those in front of the camera), the open note last so it draws on top.
    var notePins: [(note: ReviewNote, point: CGPoint)] {
        _ = viewRevision
        _ = displayRevision
        guard together.notesShown, let stage else { return [] }
        let scene = displayed.scene
        let pins = baseScene.notes.compactMap { note -> (note: ReviewNote, point: CGPoint)? in
            stage.screenPoint(of: note.position(in: scene)).map { (note, $0) }
        }
        return pins.sorted { ($0.note.id == together.openNote ? 1 : 0) < ($1.note.id == together.openNote ? 1 : 0) }
    }

    /// Where the draft's pin is on screen.
    var draftPoint: CGPoint? {
        _ = viewRevision
        guard let draft = together.draft else { return nil }
        return stage?.screenPoint(of: draft.world)
    }
}
