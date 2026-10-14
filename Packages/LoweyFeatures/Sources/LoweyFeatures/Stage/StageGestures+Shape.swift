import LoweyCore
import LoweyEngine
import UIKit

/// U6's drags with the Model tool in the hand: the surface brushes, the knife's line, and touch modelling for hands
/// (the Pencil does the same with no tool at all, from `beginSelectDrag`).
extension StageGestures {
    /// What a drag starting here does with Model's verbs; nil leaves it to sketching, the lasso or the orbit.
    func beginShapeDrag(at point: CGPoint, editor: EditorModel, shapes: Bool) -> DragKind? {
        guard shapes, editor.modeling.mode.pickMode != nil else { return nil }
        if editor.modeling.knifeArmed {
            editor.lassoPoints = [point, point]
            return .knife(point)
        }
        switch editor.modeling.verb {
        case .brush:
            guard let id = editor.shapedSelection?.id, stage?.pickObject(at: point)?.0 == id else { return nil }
            editor.sculptBegan(at: point)
            return editor.sculpting.session == nil ? DragKind.none : .sculpt
        case .shape:
            return editor.beginPartDrag(at: point).map { .part($0) }
        case .cage, .bend, .measure:
            return nil
        }
    }

    func continueShapeDrag(to point: CGPoint, editor: EditorModel) {
        switch drag {
        case let .part(part):
            editor.continuePartDrag(part, to: point)
        case .sculpt:
            editor.sculptMoved(to: point, pressure: 1)
        case let .knife(start):
            editor.lassoPoints = [start, point]
        default:
            break
        }
    }

    func endShapeDrag(editor: EditorModel, cancelled: Bool) {
        switch drag {
        case let .part(part):
            editor.endPartDrag(part, commit: !cancelled)
        case .sculpt:
            editor.sculptEnded(commit: !cancelled)
        case let .knife(start):
            let end = editor.lassoPoints.last ?? start
            editor.lassoPoints = []
            if !cancelled { editor.knifeCut(from: start, to: end) }
        default:
            break
        }
    }
}
