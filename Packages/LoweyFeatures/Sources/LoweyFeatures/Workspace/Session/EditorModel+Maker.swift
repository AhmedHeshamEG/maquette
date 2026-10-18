import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The character maker (K1, CONTEXT §10.11): Library ▸ Characters ▸ New puts a character on the stage and its panel
/// opens on it; parts are added, restyled, taken away or drawn and modelled; every change to the parts rigs it again
/// in the same undo step; face states, proportions, a typed line and acting it out are one step deeper.
extension EditorModel {
    /// The made character the selection belongs to (the character itself or one of its parts).
    var makerCharacter: ObjectID? {
        guard let id = singleSelection?.id else { return nil }
        return CharacterMaker.character(of: id, in: baseScene)
    }

    /// The selected part of a made character.
    var selectedPart: SceneObject? {
        guard let object = singleSelection, object.part != nil, makerCharacter != nil else { return nil }
        return object
    }

    /// What Core can't measure itself: a placed model's shape, from its loaded parts.
    func makerBounds(_ object: SceneObject) -> Bounds? {
        if let bounds = CharacterAnatomy.coreBounds(object) { return bounds }
        let parts = ModelExport.localParts(object, look: look, catalog: library.catalog, models: library.models)
        return Bounds(points: parts.flatMap { $0.mesh.positions.map { Vec3($0) } })
    }

    /// A new character from a start, where new things land, selected with its panel open.
    func newCharacter(_ start: CharacterStart) {
        var ids = IDFactory.random
        let name = ObjectFactory.uniqueName(start == .nothing ? "Creature" : start.title, in: baseScene)
        let fragment = CharacterMaker.start(start, name: name, at: dropPoint(), ids: &ids)
        let root = fragment.roots[0]
        let insert = EditCommand.insert(fragment, parent: nil, index: nil)
        guard perform(CharacterAutoRig.rigging(after: insert, root: root, in: document, label: "New \(start.title.lowercased())")) else { return }
        select(root)
        foldInspector(false)
        traceRig(root)
        HmmHaptics.play(.commit)
        if start == .nothing {
            app.show("Add its first part from its panel: an eye makes a creature")
        } else {
            app.show("\(name) is here. Its parts are in its panel")
        }
    }

    /// Adds a part to the selected character, or to the selected thing (which becomes a character's body).
    func addPart(_ job: CharacterPart.Job, style: String? = nil) {
        guard let target = makerCharacter ?? singleSelection?.id else {
            app.show("Pick a character or a thing first")
            return
        }
        var ids = IDFactory.random
        guard let change = CharacterMaker.add(job, style: style, to: target, symmetric: maker.symmetric, in: baseScene, ids: &ids,
                                              shapeBounds: { self.makerBounds($0) }) else { return }
        let label = "Add \(job.title.lowercased())"
        if perform(CharacterAutoRig.rigging(after: change.command, root: change.root, in: document, label: label)) {
            if makerCharacter != change.root { select(change.root) }
            traceRig(change.root)
            HmmHaptics.play(.commit)
        }
    }

    /// Under UI tests, how many joints the character rigged itself with (the debug trail).
    private func traceRig(_ root: ObjectID) {
        if AppIdentity.isUITesting { trail("rig=\(baseScene.objects[root]?.rig?.skeleton.joints.count ?? 0)") }
    }

    func restyleSelectedPart(_ style: String) {
        guard let part = selectedPart, let root = makerCharacter else { return }
        var ids = IDFactory.random
        guard let change = CharacterMaker.restyle(part.id, to: style, mirrored: maker.symmetric, in: baseScene, ids: &ids) else { return }
        perform(CharacterAutoRig.rigging(after: change, root: root, in: document, label: change.label))
    }

    func removeSelectedPart() {
        guard let part = selectedPart, let root = makerCharacter else { return }
        let change = CharacterMaker.remove(part.id, mirrored: maker.symmetric, in: baseScene)
        if perform(CharacterAutoRig.rigging(after: change, root: root, in: document, label: "Remove \(part.name.lowercased())")) { select(root) }
    }

    /// The selected thing (drawn or modelled) becomes a part of the character nearest it, or the drawing of a face state.
    func makeSelectionPart(_ job: CharacterPart.Job, shows state: String? = nil, of character: ObjectID? = nil) {
        guard let thing = singleSelection, let root = character ?? nearestCharacter(to: thing.id) else {
            app.show("Put it on a character first")
            return
        }
        guard let change = CharacterMaker.assign(thing.id, as: job, shows: state, character: root, in: baseScene) else { return }
        perform(CharacterAutoRig.rigging(after: change, root: root, in: document, label: change.label))
    }

    /// The made character closest to a thing (the one it was drawn on).
    func nearestCharacter(to id: ObjectID) -> ObjectID? {
        if let own = CharacterMaker.character(of: id, in: baseScene) { return own }
        let at = baseScene.worldTransform(of: id).position
        return baseScene.objects.values.filter { $0[.characterStart] != nil }
            .min { baseScene.worldTransform(of: $0.id).position.distance(to: at) < baseScene.worldTransform(of: $1.id).position.distance(to: at) }?.id
    }

    // MARK: Face states

    /// Shows a face state on the stage (a live value, never a key) until another is shown or the panel lets go.
    func previewFaceState(_ job: CharacterPart.Job, _ state: String?) {
        guard let root = makerCharacter else { return }
        if let old = maker.preview { clearPreview(old) }
        guard let state else {
            maker.preview = nil
            refreshDisplay()
            return
        }
        maker.preview = MakerState.FacePreview(character: root, job: job, state: state)
        switch job {
        case .mouth: propertyOverride[root, default: [:]][.mouthShape] = .enumeration(state)
        case .brow: propertyOverride[root, default: [:]][.browState] = .enumeration(state)
        case .eye:
            propertyOverride[root, default: [:]][.blinkLeft] = .float(state == "blink" ? 1 : 0)
            propertyOverride[root, default: [:]][.blinkRight] = .float(state == "blink" ? 1 : 0)
        default: break
        }
        refreshDisplay()
    }

    private func clearPreview(_ preview: MakerState.FacePreview) {
        for key in [PropertyKey.mouthShape, .browState, .blinkLeft, .blinkRight] {
            propertyOverride[preview.character]?[key] = nil
        }
    }

    /// Changes the shown state of the selected face part (and its mirror's when symmetric), one undo step per drag.
    func setFaceBend(_ state: String, _ bend: FaceBend?, gesture: String? = nil) {
        guard let part = selectedPart else { return }
        perform(CharacterMaker.setState(state, of: part.id, to: bend, mirrored: maker.symmetric, in: baseScene), coalesceKey: gesture)
    }

    // MARK: Proportions

    /// Changes a measure by a factor; during a drag every step joins one undo step and the rig follows when it ends.
    func changeProportion(_ measure: CharacterProportions.Measure, by factor: Double, gesture: String?, side: CharacterPart.Side? = nil) {
        guard let root = makerCharacter, let anatomy = CharacterAnatomy(root, in: baseScene, shapeBounds: { self.makerBounds($0) }) else { return }
        perform(CharacterProportions.change(measure, by: factor, anatomy: anatomy, scene: baseScene, side: maker.symmetric ? nil : side),
                coalesceKey: gesture)
        if gesture == nil { rigAgain(root, gesture: nil) }
    }

    /// The measures of the selected character, in metres.
    var proportions: [CharacterProportions.Measure: Double] {
        guard let root = makerCharacter, let anatomy = CharacterAnatomy(root, in: baseScene, shapeBounds: { self.makerBounds($0) }) else { return [:] }
        return CharacterProportions.measure(anatomy, rootScale: baseScene.worldTransform(of: root).scale.y)
    }

    /// The rig built again from the parts as they stand (after a drag of parts or proportions).
    func rigAgain(_ root: ObjectID, gesture: String?) {
        perform(CharacterAutoRig.command(root, in: baseScene, shapeBounds: { self.makerBounds($0) }), coalesceKey: gesture)
    }

    /// After parts of a made character were moved, turned or sized by hand: it rigs itself again, in the same step.
    func rigMovedParts(gesture: String) {
        let roots = Set(selection.compactMap { id -> ObjectID? in
            guard let root = CharacterMaker.character(of: id, in: baseScene), root != id else { return nil }
            return root
        })
        for root in roots {
            rigAgain(root, gesture: gesture)
        }
    }

    // MARK: Saying and acting

    /// The selected character says a typed line from the playhead (lip sync with no voice).
    func sayLine(_ text: String) {
        guard let root = makerCharacter ?? singleSelection?.id else { return }
        var ids = IDFactory.random
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, perform(LipSync.line(words, character: root, from: time, language: transcriptLanguage, timeline: timeline, ids: &ids)) else {
            return
        }
        HmmHaptics.play(.commit)
    }

    /// Whether the selected character can act things out (a person: the humanoid joints).
    var canActOut: Bool {
        guard let root = makerCharacter ?? singleSelection?.id else { return false }
        return baseScene.objects[root]?.rig?.standard == .humanoid
    }

    /// Reads a video of a person and keys the selected character to copy the body, from the playhead.
    func actOut(from url: URL) {
        guard let root = makerCharacter ?? singleSelection?.id, let object = baseScene.objects[root], let rig = object.rig else { return }
        maker.reading = 0
        let fps = Double(timeline.fps)
        let report: @Sendable (Double) -> Void = { [weak self] value in
            guard let self else { return }
            Task { @MainActor in self.maker.reading = value }
        }
        Task {
            do {
                let frames = try await BodyPoseReader.frames(of: url, fps: fps, progress: report)
                maker.reading = nil
                var ids = IDFactory.random
                if perform(ActOut.keys(frames, rig: rig, character: object, from: time, mirrored: maker.mirrored, timeline: timeline, ids: &ids)) {
                    app.show("\(object.name) copies \(frames.count) frames of you", kind: .success)
                }
            } catch {
                maker.reading = nil
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                app.show(String.LocalizationValue(message), kind: .error)
            }
        }
    }
}

/// A proportion's handle on the stage (K1 step 4): the top of the head, a foot, a hand, the side of the waist.
struct ProportionHandle: Identifiable {
    var measure: CharacterProportions.Measure
    var point: CGPoint
    var side: CharacterPart.Side?
    var id: String { "\(measure.rawValue)-\(side?.rawValue ?? "")" }

    /// How a drag changes the measure: up makes a head bigger, down makes legs and arms longer, out widens the waist.
    func factor(for drag: CGSize) -> Double {
        switch measure {
        case .head, .height, .body: exp(-Double(drag.height) / 220)
        case .legs, .arms: exp(Double(drag.height) / 220)
        case .waist: exp(Double(drag.width) * (side == .right ? -1 : 1) / 220)
        }
    }
}

extension EditorModel {
    /// Where the proportion handles stand on the screen, while Proportions is open.
    var proportionHandles: [ProportionHandle] {
        guard maker.proportions, let root = makerCharacter, let stage,
              let anatomy = CharacterAnatomy(root, in: baseScene, shapeBounds: { self.makerBounds($0) }) else { return [] }
        let world = baseScene.worldTransform(of: root)
        func screen(_ point: Vec3) -> CGPoint? { stage.screenPoint(of: world.apply(to: point)) }
        var handles: [ProportionHandle] = []
        if let head = anatomy.head?.rootBounds, let point = screen(Vec3(head.center.x, head.max.y, head.center.z)) {
            handles.append(ProportionHandle(measure: .head, point: point))
        }
        for (job, measure) in [(CharacterPart.Job.leg, CharacterProportions.Measure.legs), (.arm, .arms)] {
            for limb in anatomy.limbs(job) where limb.limb.isEmpty || limb.limb == "front" {
                guard let end = anatomy.limb(job, side: limb.side, limb: limb.limb).last?.rootBounds,
                      let point = screen(Vec3(end.center.x, end.min.y, end.center.z)) else { continue }
                handles.append(ProportionHandle(measure: measure, point: point, side: limb.side))
            }
        }
        if let body = anatomy.body?.rootBounds {
            for side in [CharacterPart.Side.left, .right] {
                let x = side == .left ? body.max.x : body.min.x
                if let point = screen(Vec3(x, body.center.y, body.center.z)) { handles.append(ProportionHandle(measure: .waist, point: point, side: side)) }
            }
        }
        return handles
    }
}
