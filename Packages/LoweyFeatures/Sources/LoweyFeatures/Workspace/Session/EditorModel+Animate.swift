import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// A path being drawn (A1): the thing it moves, how high its pivot sits above what it stands on, the plane it falls
/// back to over empty space, and the samples so far.
struct MotionDrawing: Equatable, Sendable {
    var id: ObjectID
    var lift: Double
    var height: Double
    var points: [Vec3] = []
    var times: [TimeInterval] = []
}

/// Animate (A1): its bar (Path · Look at · Pick up · Properties · Ghosts · Dope sheet), a motion drawn with the Pencil
/// at the speed it was drawn, looking at things, picking up and handing off.
extension EditorModel {
    /// Animate is on and its bar is in reach (Select or Path in the hand).
    var animatesNow: Bool { animate.isOn && (tool == .select || tool == .animate) }

    /// The path the Pencil is drawing, while it draws.
    var motionDrawing: MotionDrawing? {
        get { animate.path }
        set { animate.path = newValue }
    }

    /// The ruler is being dragged (ghosts show while scrubbing).
    var scrubbingTimeline: Bool {
        get { animate.scrubbing }
        set { animate.scrubbing = newValue }
    }

    /// Motion rows or the dope sheet, remembered on the device.
    var timelineStyle: TimelineStyle {
        get { animate.style }
        set {
            animate.style = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: TimelineStyle.key)
        }
    }

    /// Each animated thing's motion curve for the timeline's rows (made again when the document changes).
    var motionCurves: (revision: Int, curves: [ObjectID: [Double]]) {
        get { motionCache.curves }
        set { motionCache.curves = newValue }
    }

    /// Animate's button: the timeline and the bar come, or go (with the timeline folded away, it comes back first).
    func toggleAnimate() {
        HmmHaptics.play(.selection)
        openPanel = nil
        if animatesNow, timelinePresence == .full {
            animate.isOn = false
            animate.verb = nil
            if tool == .animate { tool = .select }
            timelinePresence = .transport
        } else {
            animate.isOn = true
            if tool != .select { tool = .select }
            timelinePresence = .full
        }
    }

    /// A verb of the bar: tap it again to put it down (the Pencil picks and moves things again).
    func chooseAnimateVerb(_ verb: AnimateVerb) {
        HmmHaptics.play(.selection)
        animate.verb = animate.verb == verb ? nil : verb
        tool = animate.verb == .path ? .animate : .select
        if let chosen = animate.verb, selection.count != 1 { app.show("Pick the one thing first. \(chosen.hint)") }
    }

    /// The thing a verb works on: the one selected thing, if it can move.
    var animateSubject: ObjectID? {
        guard selection.count == 1, let id = selection.first, !baseScene.isEffectivelyLocked(id) else { return nil }
        return id
    }

    /// The ruler let go: the scrubbing ghosts leave.
    func endScrub() {
        guard scrubbingTimeline else { return }
        scrubbingTimeline = false
        refreshDisplay()
    }

    // MARK: Drawing a path

    /// A path starts: its thing's pivot rides as high above what it stands on as it does now.
    func beginDrawnMotion() -> Bool {
        guard let id = animateSubject else {
            app.show("Pick the thing that moves, then draw where it goes")
            return false
        }
        let pivot = displayed.scene.worldTransform(of: id).position
        let bottom = stage?.visualBounds(of: [id])?.min.y ?? pivot.y
        motionDrawing = MotionDrawing(id: id, lift: pivot.y - bottom, height: bottom)
        animate.drawing = []
        pause()
        return true
    }

    /// Samples of the stroke (a batch a frame): level with the surface under the batch's last point (a thing's own
    /// surface doesn't count; one look at the ID buffer a frame), else with where it last stood.
    func addMotionSamples(_ samples: [(point: CGPoint, time: TimeInterval)]) {
        guard var drawing = motionDrawing, let stage, let last = samples.last else { return }
        let moving = Set(baseScene.subtree(of: drawing.id))
        if let (hit, surface) = stage.pickObject(at: last.point), !moving.contains(hit), surface.normal.y > 0.35 {
            drawing.height = surface.point.y
        }
        var drawn: [CGPoint] = []
        for sample in samples {
            guard let landed = stage.groundPoint(at: sample.point, height: drawing.height) else { continue }
            drawing.points.append(landed + Vec3(0, drawing.lift, 0))
            drawing.times.append(sample.time)
            drawn.append(sample.point)
        }
        motionDrawing = drawing
        animate.drawing += drawn
    }

    /// The stroke ends: the keys land from the playhead, timed as it was drawn.
    func finishDrawnMotion() {
        defer {
            motionDrawing = nil
            animate.drawing = []
        }
        guard let drawing = motionDrawing, let first = drawing.times.first else { return }
        let samples = zip(drawing.points, drawing.times).map { DrawnMotion.Sample(point: $0, time: $1 - first) }
        let object = baseScene.objects[drawing.id]
        let upright = object?[.characterStart] != nil || CharacterRig.of(drawing.id, in: baseScene, rigs: rigs()) != nil
        let options = DrawnMotion.Options(facesTheWay: animate.facesTheWay, banks: animate.banks, upright: upright)
        var ids = IDFactory.random
        guard let command = DrawnMotion.keys(samples, object: drawing.id, in: document, from: time, options: options, ids: &ids) else {
            app.show("Draw a little longer: that was too short to move along")
            return
        }
        perform(command)
        HmmHaptics.play(.commit)
    }

    func cancelDrawnMotion() {
        motionDrawing = nil
        animate.drawing = []
    }

    // MARK: Changing it

    /// How long the selection's motion lasts, first key to last.
    var motionDuration: Double? {
        animateSubject.flatMap { DrawnMotion.span(of: $0, in: timeline)?.duration }
    }

    func retimeMotion(to duration: Double, gesture: String) {
        guard let id = animateSubject, let command = DrawnMotion.retiming(id, to: duration, in: timeline) else { return }
        perform(command, coalesceKey: gesture)
    }

    func evenSpeed() {
        guard let id = animateSubject, let command = DrawnMotion.evenSpeed(id, in: timeline) else { return }
        perform(command)
        HmmHaptics.play(.commit)
    }

    func turnFront() {
        guard let id = animateSubject, let command = DrawnMotion.turningFront(id, quarterTurns: 1, in: timeline) else { return }
        perform(command)
    }
}
