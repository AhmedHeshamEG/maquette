import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// "Rig as a person" (CONTEXT §10.10: guess, then fix): the stage turns to the model's front and the dots land where
/// the shape says the joints are (head, chin, shoulders, elbows, wrists, hips, knees, ankles); the wrong ones are
/// dragged, and Rig builds a humanoid skeleton through the middle of the limbs, so every built-in clip plays on it.
/// A person rig opens again with its own dots, to be moved.
extension EditorModel {
    /// Starts placing a person's dots on the object: its own when it's a person already, else the guess.
    func startPersonRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id] else { return }
        if let blocker = rigBlocker(object) {
            app.show(String.LocalizationValue(blocker))
            return
        }
        if case .drawing = object.kind {
            app.show("Tap the joints of a drawing with the Pencil")
            return
        }
        guard let mesh = rigSurfaceMesh(of: object), let bounds = mesh.bounds else {
            app.show("This model hasn't loaded yet")
            return
        }
        rigging.target = id
        rigging.mode = .marks
        let existing = object.rig.flatMap(HumanRig.dots(of:))
        rigging.person = PersonRigging(target: id, dots: existing ?? HumanRig.template(bounds: bounds), placed: Set(HumanRig.Dot.allCases),
                                       found: existing != nil, bounds: bounds)
        tool = .rig
        openPanel = nil
        lookAtFront(of: id, bounds: bounds)
        guard existing == nil else { return }
        // The guess runs off the main thread; the usual places stand in until it lands.
        rigging.guessing = id
        Task {
            let guess = await Task.detached(priority: .userInitiated) { BodyGuess.person(BodyGuess.points(of: mesh), bounds: bounds) }.value
            guard rigging.guessing == id, var person = rigging.person, person.target == id else { return }
            rigging.guessing = nil
            if let guess {
                person.dots = guess
                person.found = true
                rigging.person = person
            }
        }
    }

    /// The stage looks straight at the object's front (its +z), the whole of it in view.
    private func lookAtFront(of id: ObjectID, bounds: Bounds) {
        guard let stage else { return }
        let frame = rigFrame(id)
        let front = frame.applyDirection(.unitZ)
        let centre = frame.apply(to: bounds.center)
        let size = bounds.size.scaled(by: Vec3(abs(frame.scale.x), abs(frame.scale.y), abs(frame.scale.z)))
        var view = stage.viewpoint
        view.target = centre
        view.yaw = atan2(front.x, front.z) * 180 / .pi
        view.pitch = 0
        view.distance = max(size.y, size.x) * 1.6 / max(tan(view.fieldOfView * .pi / 360), 0.05)
        stage.animate(to: view)
    }

    /// Where a point on the stage lands on the plane through the model's middle, facing its front (rig space).
    private func personPoint(at point: CGPoint, person: PersonRigging) -> Vec3? {
        let frame = rigFrame(person.target)
        guard let ray = rigRay(at: point, frame: frame) else { return nil }
        return GuideSurface.plane(origin: person.bounds.center, normal: .unitZ).intersect(ray)?.point
    }

    /// A tap with the Pencil moves the dot nearest it there (the guess placed them all).
    func personTap(at point: CGPoint) {
        guard rigging.person != nil, let nearest = personDotsOnScreen().min(by: {
            hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y)
        }), hypot(nearest.point.x - point.x, nearest.point.y - point.y) < 80 else { return }
        movePersonDot(nearest.dot, to: point)
        HmmHaptics.play(.selection)
    }

    /// A dot dragged on the stage.
    func movePersonDot(_ dot: HumanRig.Dot, to point: CGPoint) {
        guard var person = rigging.person, let spot = personPoint(at: point, person: person) else { return }
        rigging.guessing = nil
        person.dots[dot] = spot
        rigging.person = person
    }

    /// The dots on screen.
    func personDotsOnScreen() -> [(dot: HumanRig.Dot, point: CGPoint)] {
        guard let person = rigging.person, let stage else { return [] }
        let frame = rigFrame(person.target)
        return HumanRig.Dot.allCases.compactMap { dot in
            person.dots[dot].flatMap { stage.screenPoint(of: frame.apply(to: $0)) }.map { (dot, $0) }
        }
    }

    /// Builds the person's skeleton from the dots and works out its weights (one undo step, replacing any marks).
    /// Joints keep the standard names, so a person changed after posing keeps its pose and its keys.
    func finishPersonRig() {
        guard let person = rigging.person, let object = baseScene.objects[person.target], let mesh = rigSurfaceMesh(of: object) else { return }
        let far = person.bounds.max.z + person.bounds.size.length + 1
        // A dot already in a limb's middle (a person changed again) keeps its depth; a new one finds it.
        let rays = person.dots.mapValues { Ray(origin: Vec3($0.x, $0.y, far), direction: Vec3(0, 0, -1)) }
        var points = HumanRig.points(rays: rays, surface: TriangleBVH(mesh), bounds: person.bounds)
        if object.rig?.person != nil {
            for (dot, point) in person.dots where object.rig?.person?[dot.rawValue] == point {
                points[dot] = point
            }
        }
        guard let rig = HumanRig.rig(from: points, bounds: person.bounds) else {
            app.show("Place every dot first")
            return
        }
        let changing = object.rig != nil
        rigging.person = nil
        rigging.guessing = nil
        weigh(rig, on: object, label: changing ? "Change \(object.name)'s rig" : "Rig \(object.name) as a person",
              done: changing ? nil : "\(object.name) is rigged. Drag its hands and feet, or try a clip")
        tool = .select
        select(object.id)
    }

    func cancelPersonRig() {
        rigging.person = nil
        rigging.guessing = nil
    }
}
