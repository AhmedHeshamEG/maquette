import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit.UIGestureRecognizerSubclass

/// The hand shortcuts on the stage (CONTEXT §10.10): a finger held down while the Pencil works flips snapping for that
/// move, a finger's double-tap frames a thing (again: looks straight at the face it touched), and a finger that sketches
/// gets the system's magnifier so it doesn't hide the point it draws.
extension StageGestures {
    // MARK: Double-tap

    @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard HmmShortcut.frame.isOn(), let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        guard let (id, _) = stage.pickObject(at: point) else {
            lastFramed = nil
            editor.frameSelection()
            return
        }
        if lastFramed == id, let ray = stage.worldRay(at: point), let mesh = stage.worldMesh(of: id), let hit = MeshRaycast.intersect(ray, mesh: mesh) {
            editor.lookStraight(at: hit.point, normal: hit.normal)
            lastFramed = nil
            return
        }
        editor.frame(id)
        lastFramed = id
    }

    // MARK: The eyedropper

    /// A finger held on a thing while drawing: the loupe shows, follows the finger, and lifting takes the colour.
    func eyedropperPress(_ recognizer: UILongPressGestureRecognizer, editor: EditorModel, stage: StageView) {
        let point = recognizer.location(in: stage)
        switch recognizer.state {
        case .began:
            guard stage.pickObject(at: point) != nil else { return }
            editor.eyedrop(at: point)
        case .changed:
            if editor.eyedropperLoupe != nil { editor.eyedrop(at: point) }
        case .ended:
            editor.finishEyedrop()
        default:
            editor.finishEyedrop(commit: false)
        }
    }

    // MARK: The magnifier

    func startLoupe(at point: CGPoint, in stage: StageView) {
        loupe?.invalidate()
        loupe = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: nil, in: stage)
    }

    // MARK: A finger held for snapping

    /// Whether a finger resting on the stage flips the Snap magnet now (its switch on, the Pencil also down).
    func heldFingerChanged(fingerHeld: Bool, pencilDown: Bool) {
        guard let editor else { return }
        let flipped = HmmShortcut.snapWithFinger.isOn() && fingerHeld && pencilDown
        guard flipped != editor.snapFlipped else { return }
        editor.snapFlipped = flipped
        HmmHaptics.play(.selection)
    }
}

/// Watches the stage's touches without claiming them: a finger that rests (moves less than 12 points) while the Pencil
/// is down. It never recognises, delays or cancels anything.
final class HeldFingerWatcher: UIGestureRecognizer {
    var onChange: ((_ fingerHeld: Bool, _ pencilDown: Bool) -> Void)?
    private var fingers: [ObjectIdentifier: CGPoint] = [:]
    private var moved = Set<ObjectIdentifier>()
    private var pencils = Set<ObjectIdentifier>()

    func configure() {
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if touch.type == .pencil { pencils.insert(id) } else { fingers[id] = touch.location(in: view) }
        }
        report()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
        for touch in touches where touch.type != .pencil {
            let id = ObjectIdentifier(touch)
            guard let start = fingers[id] else { continue }
            let point = touch.location(in: view)
            if hypot(point.x - start.x, point.y - start.y) > 12 { moved.insert(id) }
        }
        report()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent) {
        lift(touches)
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            fingers[id] = nil
            moved.remove(id)
            pencils.remove(id)
        }
        report()
        if fingers.isEmpty, pencils.isEmpty { state = .failed }
    }

    private func report() {
        let held = fingers.keys.contains { !moved.contains($0) }
        onChange?(held, !pencils.isEmpty)
    }

    override func reset() {
        super.reset()
        fingers = [:]
        moved = []
        pencils = []
        onChange?(false, false)
    }
}
