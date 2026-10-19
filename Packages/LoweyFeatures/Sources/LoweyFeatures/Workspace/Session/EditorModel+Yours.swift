import Foundation
import HmmDesign
import LoweyCore

/// Yours on the stage (L2, law 12): a Look from Yours used in this project, effects and parts saved to Yours and put
/// back, and the ground the world stands on. Each is one undo step.
extension EditorModel {
    // MARK: Grounds

    /// Library ▸ Things ▸ Grounds: what the world's floor is made of (nil: a plain floor).
    func setGround(_ surface: GroundSurface?) {
        updateLook { $0.ground = $0.ground.made(of: surface) }
        HmmHaptics.play(.commit)
    }

    // MARK: Your Looks

    /// The next (or previous) of the project's Looks, round the list (the menu bar's Next Look).
    func stepLook(by step: Int) {
        let looks = allLooks
        guard let index = looks.firstIndex(where: { $0.id == look.presetID }), !looks.isEmpty else { return }
        let next = looks[((index + step) % looks.count + looks.count) % looks.count]
        setLookPreset(next.id)
        app.show(String.LocalizationValue(next.name))
    }

    /// A Look from Yours becomes this project's own (a copy that travels with it) and the scene's Look.
    func useStyle(_ preset: LookPreset) {
        var looks = document.project.customLooks
        if !looks.contains(where: { $0.id == preset.id }) { looks.append(preset) }
        perform(.batch("Look: \(preset.name)", [.setCustomLooks(looks), .setLook(look.withPreset(preset.id), scope: lookIsSceneOnly ? .scene : .project)]))
        HmmHaptics.play(.selection)
    }

    /// Keeps one of this project's Looks in Yours, for every project.
    func saveLookToYours(_ preset: LookPreset) {
        let kept = library.saveStyle(preset)
        app.show("“\(kept.name)” is in Yours, for every project")
    }

    // MARK: Effects

    /// Keeps the selected effect (its recipe as tuned) in Yours.
    func saveEffectToYours(_ id: ObjectID) {
        guard let object = baseScene.objects[id], case let .particles(recipe) = object.kind else { return }
        library.saveEffect(name: object.name, recipe: recipe)
        app.show("“\(object.name)” is in Yours ▸ Effects")
    }

    /// An effect from Yours placed where you look (or on the selection), as Model ▸ Add ▸ Effects places one.
    func addSavedEffect(_ saved: SavedEffect) {
        var recipe = saved.recipe
        if recipe.burst { recipe.burstTime = time }
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(saved.name, in: scene), kind: .particles(recipe))
        let anchor = selectionPivot.map { Vec3($0.x, selectionBounds?.max.y ?? $0.y, $0.z) } ?? dropPoint()
        object.transform.position = recipe.preset == .rain || recipe.preset == .snow ? Vec3(anchor.x, 0, anchor.z) : anchor
        if perform(operations.add(object)) { select(object.id) }
    }

    // MARK: Parts

    /// Keeps the selected part of a made character in Yours, as it hangs from where it attaches.
    func savePartToYours(_ id: ObjectID) async {
        guard let object = baseScene.objects[id] else { return }
        var fragment = FragmentTools.extract([id], from: baseScene)
        if let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) {
            fragment.objects[index].transform.position = .zero
        }
        let job = object.part?.job ?? .extra
        await library.savePart(name: object.name, job: job, fragment: fragment)
        app.show("“\(object.name)” is in Yours ▸ Parts")
    }

    /// A part from Yours goes onto the selected character (on its head for a face part, an ear, hair or an extra) and the
    /// character rigs itself again; with no character selected it lands as a thing, to make a part later.
    func addSavedPart(_ saved: SavedPart) {
        var ids = IDFactory.random
        var (fragment, _) = FragmentTools.reidentified(saved.fragment, ids: &ids)
        guard let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) else { return }
        guard let character = makerCharacter else {
            fragment.objects[index].transform.position = dropPoint()
            if perform(.insert(fragment, parent: nil, index: nil)) { select(root) }
            app.show("Put it on a character: its menu ▸ Make it a part")
            return
        }
        let onHead = saved.job.isFace || [.ear, .hair, .extra].contains(saved.job)
        if let bounds = SceneBounds(library: library.manifest).worldBounds(of: character, in: baseScene) {
            let height = bounds.max.y - bounds.min.y
            fragment.objects[index].transform.position = onHead ? Vec3(bounds.center.x, bounds.max.y - height * 0.15, bounds.max.z)
                : bounds.center
        }
        let insert = EditCommand.insert(fragment, parent: nil, index: nil)
        var trial = document
        guard (try? insert.apply(to: &trial)) != nil,
              let assign = CharacterMaker.assign(root, as: saved.job, character: character, in: trial.scene) else { return }
        let label = "Add \(saved.name)"
        if perform(CharacterAutoRig.rigging(after: .batch(label, [insert, assign]), root: character, in: document, label: label)) {
            select(root)
            HmmHaptics.play(.commit)
        }
    }
}
