import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Animate's taps (A1): look at what's tapped; picked up by the hand that's tapped, put down on the empty ground; and
/// any property keyed from the playhead.
extension EditorModel {
    /// A tap while Look at or Pick up is in the hand. True when it took the tap.
    func animateTap(at point: CGPoint, picked: (ObjectID, SurfaceHit)?) -> Bool {
        guard animatesNow, let verb = animate.verb, verb != .path else { return false }
        guard let subject = animateSubject else {
            app.show("Pick the one thing first, then tap")
            return true
        }
        let target = picked.flatMap { baseScene.subtree(of: subject).contains($0.0) ? nil : $0 }
        if picked != nil, target == nil { return true }
        switch verb {
        case .lookAt: look(subject, at: target?.0)
        case .pickUp: hold(subject, by: target)
        case .path: break
        }
        return true
    }

    /// Looks at `target` from the playhead (for the whole shot when it never looked at anything before).
    private func look(_ subject: ObjectID, at target: ObjectID?) {
        var ids = IDFactory.random
        let looks = baseScene.objects[subject]?[.lookAt] != nil || timeline.track(for: subject, .lookAt) != nil
        let command = looks && time > 1e-3
            ? LookAtOperations.switchLook(subject, to: target, at: time, in: baseScene, ids: &ids)
            : LookAtOperations.look(subject, at: target, at: time, in: baseScene, ids: &ids)
        guard let command else { return }
        perform(command)
        HmmHaptics.play(.commit)
        let name = target.flatMap { baseScene.objects[$0]?.name } ?? "nothing"
        app.show("\(baseScene.objects[subject]?.name ?? "It") looks at \(name) from \(TimeFormat.clock(time))")
    }

    /// Picked up (or handed on) by the tapped thing at the playhead, by the nearest joint of a skinned character;
    /// put down when the tap found nothing.
    private func hold(_ subject: ObjectID, by holder: (ObjectID, SurfaceHit)?) {
        var ids = IDFactory.random
        let name = baseScene.objects[subject]?.name ?? "It"
        guard let (holderID, hit) = holder else {
            guard let command = HoldOperations.putDown(subject, at: time, timeline: timeline, ids: &ids) else {
                app.show("Nothing holds \(name) now")
                return
            }
            perform(command)
            app.show("\(name) is put down at \(TimeFormat.clock(time))")
            return
        }
        let joint = baseScene.objects[holderID]?.rig?.skin != nil || baseScene.objects[holderID]?.kind.assetID != nil
            ? HoldOperations.nearestJoint(to: hit.point, of: holderID, in: displayed, rigs: rigs()) : nil
        guard let command = HoldOperations.pickUp(subject, by: holderID, joint: joint, at: time, shown: displayed, rigs: rigs(),
                                                  timeline: timeline, ids: &ids) else {
            app.show("\(baseScene.objects[holderID]?.name ?? "That") can't hold \(name): it would hold itself", kind: .error)
            return
        }
        perform(command)
        HmmHaptics.play(.commit)
        app.show("\(baseScene.objects[holderID]?.name ?? "It") takes \(name) at \(TimeFormat.clock(time))")
    }

    /// Who holds the selection at the playhead, for the bar's line.
    var heldBy: String? {
        guard let subject = animateSubject, let hold = HoldOperations.holder(of: subject, at: time, in: timeline), let holder = hold.holder else {
            return nil
        }
        return baseScene.objects[holder]?.name
    }

    // MARK: Any property

    /// What the selection can have keyed.
    var animatableChoices: [PropertyAnimation.Choice] {
        guard let id = animateSubject, let object = baseScene.objects[id] else { return [] }
        return PropertyAnimation.choices(for: object, in: baseScene)
    }

    func isAnimated(_ key: PropertyKey) -> Bool {
        animateSubject.map { timeline.track(for: $0, key) != nil } ?? false
    }

    /// A key of the property at the playhead, as it is now: from here on changing it keys itself.
    func keyProperty(_ key: PropertyKey) {
        var ids = IDFactory.random
        guard let id = animateSubject,
              let command = PropertyAnimation.key(key, of: id, at: time, shown: displayed.scene, timeline: timeline, ids: &ids) else { return }
        perform(command)
        HmmHaptics.play(.commit)
    }
}
