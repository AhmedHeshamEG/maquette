import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Motion as library material (CONTEXT §10.10): a pose, a clip or a loop is saved from its menu and dropped from the
/// Library's Motion page onto anything; on a rig of another kind it plays where the joints match and says which it
/// skipped.
extension EditorModel {
    /// A saved pose of a character, into the Library.
    func savePoseToLibrary(_ pose: CharacterPose, of character: ObjectID) {
        let standard = CharacterRig.of(character, in: baseScene, rigs: libraryRigs())?.standard ?? .custom
        let joints = pose.joints.mapValues { [Keyframe(time: 0, value: .quat($0))] }
        guard !joints.isEmpty else {
            app.show("This pose has no joints to keep")
            return
        }
        library.addMotion(MotionItem(id: UUID().uuidString.lowercased(), name: pose.name, kind: .pose, standard: standard, joints: joints))
        app.show("“\(pose.name)” is in the Library")
    }

    /// A thing's whole animation (its joints' keys and its own move and turn), into the Library as a clip or a loop.
    func saveMotionToLibrary(of character: ObjectID, loops: Bool) {
        guard let object = baseScene.objects[character] else { return }
        let name = loops ? "\(object.name) loop" : "\(object.name) move"
        guard let item = MotionLibrary.clip(of: character, in: baseScene, timeline: timeline, loops: loops, rigs: libraryRigs(),
                                            id: UUID().uuidString.lowercased(), name: name) else {
            app.show("Key a move first: there's nothing to keep yet")
            return
        }
        library.addMotion(item)
        app.show("“\(name)” is in the Library")
    }

    /// Drops a motion on the selected thing: a pose turns its joints (keyed like any change), a clip or a loop lays its
    /// keys at the playhead (a loop loops forever).
    func applyMotion(_ item: MotionItem) {
        guard let character = poseCharacter ?? singleSelection.flatMap({ CharacterRig.of($0.id, in: baseScene, rigs: libraryRigs()) != nil ? $0.id : nil })
        else {
            app.show("Choose something with joints first")
            return
        }
        let skipped: [String]
        switch item.kind {
        case .pose:
            let (changes, missed) = MotionLibrary.poseChanges(item, to: character, in: displayed.scene, rigs: libraryRigs())
            skipped = missed
            guard !changes.isEmpty else { return reportNothingMatched() }
            perform(.batch("Pose: \(item.name)", [.setProperties(changes)]))
        case .clip, .loop:
            let (edits, missed) = MotionLibrary.applying(item, to: character, at: time, in: baseScene, timeline: timeline, rigs: libraryRigs()) {
                TrackID.make()
            }
            skipped = missed
            guard !edits.isEmpty else { return reportNothingMatched() }
            perform(.batch("Drop “\(item.name)”", [.setTracks(edits)]))
        }
        library.markMotionUsed(item.id)
        HmmHaptics.play(.commit)
        if !skipped.isEmpty {
            let names = skipped.prefix(4).joined(separator: ", ") + (skipped.count > 4 ? "…" : "")
            app.show("Played where the joints match. Skipped: \(names)")
        }
    }

    /// A model that just came in (Open in, the share sheet, a drop, Home's import): placed where it was dropped (or
    /// in front), chosen, painted at once when it carries its own colours (a sculpt arrives painted), and offered
    /// "Rig it" once.
    func land(_ asset: LibraryAsset, at point: CGPoint? = nil) {
        place(.asset(asset), at: point)
        guard let object = singleSelection, object.kind.assetID == asset.id else { return }
        rigItOffer = object.id
        let id = object.id
        Task {
            guard let model = await library.models.load(asset, catalog: library.catalog), model.hasVertexColors else { return }
            preparePaint(id)
        }
    }

    /// "Rig it": the Rig panel for the model, its body shortcuts first.
    func takeRigItOffer() {
        guard let id = rigItOffer else { return }
        rigItOffer = nil
        if selection != [id] { setSelection([id]) }
        openPanel = .rig
    }

    private func reportNothingMatched() {
        app.show("None of its joints match this one's", kind: .error)
    }
}
