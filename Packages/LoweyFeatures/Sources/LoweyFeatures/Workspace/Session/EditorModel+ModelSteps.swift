import HmmDesign
import LoweyCore

/// H1: the steps list over the history scrubber. The selected modelled thing's steps; changing a step's number replays
/// the steps after it off the main thread and lands as one undo step.
extension EditorModel {
    /// The modelled thing whose steps History lists: the one selected, when it has steps.
    var stepsObject: SceneObject? {
        guard selection.count == 1, let id = selection.first, let object = baseScene.objects[id], object.modelHistory != nil else { return nil }
        return object
    }

    /// Changes number `number` of step `index` (counting the steps that can change) to `metres`. True when it landed.
    func changeStep(of id: ObjectID, step index: Int, number: Int, to metres: Double) async -> Bool {
        let scene = baseScene
        let units = units
        let started = scene.objects[id]
        let result = await Task.detached(priority: .userInitiated) { () -> Result<EditCommand, ModelingOperations.HistoryFailure> in
            do throws(ModelingOperations.HistoryFailure) {
                return try .success(ModelingOperations.changeStep(id, step: index, number: number, to: metres, in: scene) { units.format($0) })
            } catch {
                return .failure(error)
            }
        }.value
        // Something else changed it meanwhile: this replay is about a shape that's gone.
        guard baseScene.objects[id] == started else { return false }
        switch result {
        case let .success(command):
            let reopen = historyScrub != nil
            guard perform(command) else { return false }
            if reopen { openHistory() }
            HmmHaptics.play(.commit)
            if AppIdentity.isUITesting { trail("step=\(index + 1)") }
            return true
        case let .failure(failure):
            app.show(String.LocalizationValue(failure.description), kind: .error)
            HmmHaptics.play(.error)
            return false
        }
    }
}
