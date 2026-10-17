import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Pins and dots (CONTEXT §10.10, U4): the Pencil taps a dot on a joint or a pin where a soft thing holds or bends; a
/// stroke along a part lays a chain; a mark dragged moves, a mark held goes. Every change builds the skeleton again
/// from the marks (`RigMarks`), names kept, so poses and keys survive, and the skin updates itself in the background.
extension EditorModel {
    // MARK: The marks

    /// The marks of a thing as they stand now: the newest change being weighed, else its rig's.
    func shownMarks(of object: SceneObject) -> [RigMark] {
        if let pending = rigging.weighing[object.id] { return RigMarks.marks(of: pending) }
        return object.rig.map(RigMarks.marks(of:)) ?? []
    }

    /// Starts rigging a thing with pins and dots (the Rig tool). A rigged thing relaxes to its rest shape and shows its
    /// marks; a person rig shows its dots.
    func startMarking(_ id: ObjectID, kind: RigMark.Kind? = nil) {
        guard let object = baseScene.objects[id] else { return }
        if let blocker = rigBlocker(object) {
            app.show(String.LocalizationValue(blocker))
            return
        }
        // A made person keeps its dots (K1); a person rigged by its fourteen dots opens on them.
        if let rig = object.rig, rig.standard == .humanoid, object[.characterStart] == nil {
            startPersonRig(id)
            return
        }
        rigging.target = id
        rigging.mode = .marks
        rigging.person = nil
        if let kind { rigging.markKind = kind }
        rigging.current = shownMarks(of: object).last?.name
        if selection != [id] { setSelection([id]) }
        tool = .rig
        openPanel = nil
    }

    /// The marks changed: the skeleton is built again from them and stored (weighed in the background).
    func storeMarks(_ marks: [RigMark], on object: SceneObject, label: String) {
        let old = rigging.weighing[object.id] ?? object.rig
        let points = boneSurface(of: object)?.points ?? []
        guard !marks.isEmpty else {
            removeRig(object.id)
            return
        }
        let rig = RigMarks.rig(marks, surface: points)
        let gone = old.map { jointsGone(from: $0, in: rig) } ?? []
        weigh(rig, on: object, label: label, also: forgetting(gone, of: object))
    }

    /// Where a touch on the stage lands in the thing: the middle of the part under it, and how thick the part is there.
    func markPoint(at point: CGPoint, on object: SceneObject) -> (point: Vec3, thickness: Double)? {
        guard let stage, let ray = stage.worldRay(at: point), let surface = boneSurface(of: object) else { return nil }
        return boneSamples([ray], through: surface, of: object).first.map { ($0.point, $0.thickness) }
    }

    /// A tap with the Pencil: on a mark, it becomes the one new marks hang from; on the thing, a new mark.
    func tapMark(at point: CGPoint) {
        guard let object = rigTarget else { return }
        if let name = mark(at: point, of: object) {
            rigging.current = name
            HmmHaptics.play(.selection)
            return
        }
        guard let spot = markPoint(at: point, on: object) else { return }
        var marks = shownMarks(of: object)
        // A group holds still where it was touched first: its first dot is the middle of the part nearest the tap.
        if marks.isEmpty, case .group = object.kind, let held = heldPart(of: object, near: spot.point) {
            marks = [RigMark(name: RigMarks.rootName, kind: .dot, position: held)]
        }
        let added = RigMarks.adding(rigging.markKind, at: spot.point, thickness: spot.thickness, to: rigging.current, in: marks)
        rigging.current = added.name
        HmmHaptics.play(.selection)
        storeMarks(added.marks, on: object, label: marks.isEmpty ? "Rig \(object.name)" : (rigging.markKind == .pin ? "Add a pin" : "Add a dot"))
    }

    /// The middle of the group's part nearest a point (the group's space).
    func heldPart(of group: SceneObject, near point: Vec3) -> Vec3? {
        let frame = rigFrame(group.id)
        return group.children.compactMap { id -> Vec3? in
            guard let part = baseScene.objects[id] else { return nil }
            let local = paintSource(of: part)?.bounds?.center ?? .zero
            return frame.inverseApply(to: RigSpace.frame(of: id, in: baseScene).apply(to: local))
        }.min { $0.distance(to: point) < $1.distance(to: point) }
    }

    /// A stroke along a part: a chain of marks down its middle (pins at its ends and every few bones for a soft
    /// thing, a dot at every joint), hung from the current mark, or replacing the chain it runs along.
    func drawChain(along points: [CGPoint]) {
        guard let stage, let object = rigTarget, let surface = boneSurface(of: object) else {
            endBonePreview()
            return
        }
        let samples = boneSamples(points.compactMap { stage.worldRay(at: $0) }, through: surface, of: object)
        let joints = BoneStroke.preview(samples)
        guard joints.count >= 2 else {
            endBonePreview()
            app.show("Drag along the part that should bend, from where it holds to its end")
            return
        }
        let thickness = samples.map(\.thickness).sorted()[samples.count / 2]
        let kept = rigging.markKind == .pin ? joints.enumerated().filter { $0.offset % 3 == 0 || $0.offset == joints.count - 1 }.map(\.element) : joints
        var marks = shownMarks(of: object)
        var parent = rigging.current
        // The end nearer the marks already there is where the chain starts.
        let positions = marks.map(\.position)
        var chain = kept
        if let nearest = positions.min(by: { $0.distance(to: chain[chain.count - 1]) < $1.distance(to: chain[chain.count - 1]) }),
           nearest.distance(to: chain[chain.count - 1]) < nearest.distance(to: chain[0]) {
            chain.reverse()
        }
        if !marks.isEmpty { parent = marks.min { $0.position.distance(to: chain[0]) < $1.position.distance(to: chain[0]) }?.name ?? parent }
        for point in chain {
            let added = RigMarks.adding(rigging.markKind, at: point, thickness: thickness, to: parent, in: marks)
            marks = added.marks
            parent = added.name
        }
        rigging.current = parent
        boneSurface = nil
        storeMarks(marks, on: object, label: "Rig a chain")
    }

    /// A mark dragged: it follows the touch through the middle of the part under it (or on the plane it stood on,
    /// off the thing), and lands when the touch lifts.
    func dragMark(_ name: String, to point: CGPoint, ended: Bool) {
        guard let object = rigTarget, let stage else { return }
        let frame = rigFrame(object.id)
        let marks = shownMarks(of: object)
        guard let mark = marks.first(where: { $0.name == name }) else { return }
        var landed = markPoint(at: point, on: object)
        if landed == nil, let ray = rigRay(at: point, frame: frame) {
            let facing = frame.inverseApply(to: Vec3(stage.camera.position)) - mark.position
            landed = GuideSurface.plane(origin: mark.position, normal: facing.normalized).intersect(ray).map { ($0.point, 0) }
        }
        guard let spot = landed else { return }
        if ended {
            rigging.dragging = nil
            storeMarks(RigMarks.moving(name, to: spot.point, thickness: spot.thickness > 0 ? spot.thickness : nil, in: marks), on: object,
                       label: "Move a mark")
            boneSurface = nil
        } else {
            rigging.dragging = RigSettings.MarkDrag(name: name, position: spot.point, thickness: spot.thickness)
        }
    }

    /// A mark held: it goes (what hung from it hangs from the mark above).
    func removeMark(_ name: String) {
        guard let object = rigTarget else { return }
        let marks = RigMarks.removing(name, from: shownMarks(of: object))
        if rigging.current == name { rigging.current = marks.last?.name }
        HmmHaptics.play(.commit)
        storeMarks(marks, on: object, label: "Remove a mark")
    }

    /// A mark turned into the other kind (a dot into a pin, or back).
    func toggleMarkKind(_ name: String) {
        guard let object = rigTarget, let mark = shownMarks(of: object).first(where: { $0.name == name }) else { return }
        storeMarks(RigMarks.setting(name, to: mark.kind == .dot ? .pin : .dot, in: shownMarks(of: object)), on: object,
                   label: mark.kind == .dot ? "Make it a pin" : "Make it a dot")
    }

    /// The mark under a touch (within a finger's width), if any.
    func mark(at point: CGPoint, of object: SceneObject) -> String? {
        marksOnScreen().filter { hypot($0.point.x - point.x, $0.point.y - point.y) < 24 }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?.mark.name
    }

    /// The marks on screen (a dragged one where the touch has it).
    func marksOnScreen() -> [(mark: RigMark, point: CGPoint)] {
        guard tool == .rig, rigging.mode == .marks, rigging.person == nil, let object = rigTarget, let stage else { return [] }
        let frame = rigFrame(object.id)
        return shownMarks(of: object).compactMap { mark in
            let position = rigging.dragging?.name == mark.name ? rigging.dragging?.position ?? mark.position : mark.position
            return stage.screenPoint(of: frame.apply(to: position)).map { (mark, $0) }
        }
    }

    // MARK: Body shortcuts

    /// Four legs or wings: the dots guessed from the shape (quietly, off the main thread), or in the usual places when
    /// the shape can't be read; drag the wrong ones. A chain waits for one stroke along the part.
    func startBody(_ body: BodyShortcut, on id: ObjectID) {
        guard let object = baseScene.objects[id] else { return }
        switch body {
        case .person:
            startPersonRig(id)
        case .chain:
            startMarking(id, kind: .pin)
        case .fourLegs, .wings:
            startMarking(id, kind: .dot)
            guard let mesh = rigSurfaceMesh(of: object), let bounds = mesh.bounds else { return }
            rigging.guessing = id
            let kind: BodyGuess.Body = body == .fourLegs ? .fourLegs : .wings
            Task {
                let marks = await Task.detached(priority: .userInitiated) {
                    BodyGuess.marks(kind, vertices: BodyGuess.points(of: mesh), bounds: bounds).marks
                }.value
                guard rigging.guessing == id, let fresh = baseScene.objects[id] else { return }
                rigging.guessing = nil
                rigging.current = marks.last?.name
                storeMarks(marks, on: fresh, label: body == .fourLegs ? "Rig four legs" : "Rig wings")
            }
        }
    }
}

/// The whole-body shortcuts (CONTEXT §10.10: Person, Chain, Four legs, Wings).
enum BodyShortcut: String, CaseIterable, Identifiable {
    case person, chain, fourLegs, wings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: "Person"
        case .chain: "Chain"
        case .fourLegs: "Four legs"
        case .wings: "Wings"
        }
    }

    var systemImage: String {
        switch self {
        case .person: "figure.stand"
        case .chain: "point.topleft.down.to.point.bottomright.curvepath"
        case .fourLegs: "pawprint"
        case .wings: "bird"
        }
    }
}
