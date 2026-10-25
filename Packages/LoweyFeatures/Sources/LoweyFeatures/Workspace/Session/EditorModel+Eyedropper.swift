import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Where the eyedropper's loupe is, and the colour under it.
struct EyedropperLoupe: Equatable {
    var point: CGPoint
    var colour: RGBA
}

/// The eyedropper, Procreate's (U5, CONTEXT §10.11): while drawing, a finger held on a thing shows a ring above it,
/// the colour under the finger in its top half and the colour in the hand in its bottom half; it follows the finger and
/// lifting takes the colour. The quick menu's Eyedropper takes it from the next tap.
extension EditorModel {
    /// The colour of what is under a point: its paint where it's painted, else its own colour (nil over nothing).
    func colour(at point: CGPoint) -> RGBA? {
        guard let stage else { return nil }
        return colour(at: point, in: stage)
    }

    /// The same, for any stage view showing this project (the Reference window's Canvas too).
    func colour(at point: CGPoint, in stage: StageView) -> RGBA? {
        guard let picked = stage.pickObject(at: point), let object = displayed.scene.objects[picked.0] else { return nil }
        let local = displayed.scene.worldTransform(of: picked.0).inverseApply(to: picked.1.point)
        if let paint = object.paint, let painted = PaintSampler.color(at: local, of: object, paint: paint, file: paintFiles) {
            return RGBA(painted.r, painted.g, painted.b, 1)
        }
        guard let own = object.color?.resolved(in: look.palette) else { return nil }
        return RGBA(own.r, own.g, own.b, 1)
    }

    /// The loupe goes to a point (it starts there, or follows the finger); off every thing it keeps the last colour.
    func eyedrop(at point: CGPoint) {
        guard let colour = colour(at: point) ?? eyedropperLoupe?.colour else { return }
        if eyedropperLoupe == nil { HmmHaptics.play(.selection) }
        eyedropperLoupe = EyedropperLoupe(point: point, colour: colour)
    }

    /// The finger lifted: the colour under it is the one in the hand.
    func finishEyedrop(commit: Bool = true) {
        defer {
            eyedropperLoupe = nil
            eyedropping = false
        }
        guard commit, let picked = eyedropperLoupe?.colour else { return }
        currentColor = .rgba(picked)
        HmmPencilHaptics.buzz(at: eyedropperLoupe?.point)
    }
}
