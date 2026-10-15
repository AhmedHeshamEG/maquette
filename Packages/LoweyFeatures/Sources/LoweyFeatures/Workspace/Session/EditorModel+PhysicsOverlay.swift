import Foundation
import LoweyCore
import LoweyEngine

/// The physics marks on the stage (never exported): the selected thing's joints, speed and force arrows while the run
/// plays (Real ▸ Show the forces), and "does it stand?": the centre of mass, a plumb line and the footprint.
extension EditorModel {
    static let speedColour = RGBA(0.42, 0.78, 1)
    static let forceColour = RGBA(1, 0.62, 0.28)

    func refreshPhysicsOverlay() {
        guard let stage else { return }
        var overlays: [EditorOverlay] = []
        let shown = displayed.scene
        let width = stage.worldPerPoint(at: selectionPivot ?? .zero) * 1.5
        var joints = MeshData()
        for joint in selectedJoints {
            guard shown.objects[joint.first] != nil else { continue }
            let first = shown.worldTransform(of: joint.first)
            let anchor = first.apply(to: joint.anchor)
            ModelOverlay.dot(anchor, radius: width * 4, into: &joints)
            switch joint.kind {
            case .hinge, .slider:
                let axis = first.applyDirection(joint.axis).normalized
                ModelOverlay.line(anchor - axis * 0.15, anchor + axis * 0.15, width: width, into: &joints)
            case .spring, .rope:
                let other = joint.otherAnchor.map { point in joint.second.map { shown.worldTransform(of: $0).apply(to: point) } ?? point } ?? anchor
                ModelOverlay.line(anchor, other, width: width, into: &joints)
            case .ball, .glue, .gear:
                break
            }
        }
        if !joints.isEmpty { overlays.append(EditorOverlay(mesh: joints, color: StageColors.selection, onTop: true)) }
        overlays += arrowOverlays(width: width)
        if let stands = standsOverlay(width: width) { overlays.append(stands) }
        stage.showPhysicsOverlay(overlays)
    }

    private func arrowOverlays(width: Double) -> [EditorOverlay] {
        guard physicsRun.showsArrows, let frames = physicsRun.frames else { return [] }
        var speeds = MeshData()
        var forces = MeshData()
        let gravity = max(scenePhysics.acceleration, 1)
        for arrow in PhysicsPlayback.arrows(frames, at: time) {
            let speed = arrow.velocity.length
            if speed > 0.05 {
                ModelOverlay.arrow(from: arrow.centre, direction: arrow.velocity / speed, length: min(speed * 0.2, 3), width: width * 2, into: &speeds)
            }
            // Force drawn against the thing's own weight: half a metre is as strong as gravity's pull on it.
            guard let index = frames.bodies.firstIndex(of: arrow.object), frames.masses[index] > 0 else { continue }
            let strength = arrow.force.length / (frames.masses[index] * gravity)
            if strength > 0.05 {
                ModelOverlay.arrow(from: arrow.centre, direction: arrow.force.normalized, length: min(strength * 0.5, 3), width: width * 2, into: &forces)
            }
        }
        return [EditorOverlay(mesh: speeds, color: Self.speedColour, onTop: true), EditorOverlay(mesh: forces, color: Self.forceColour, onTop: true)]
            .filter { !$0.mesh.isEmpty }
    }

    private func standsOverlay(width: Double) -> EditorOverlay? {
        guard let result = physicsRun.stability, physicsRun.stabilityOf == operations.topLevel(selection, in: baseScene) else { return nil }
        var mesh = MeshData()
        let floor = result.support.first?.y ?? 0
        ModelOverlay.dot(result.centreOfMass, radius: width * 5, into: &mesh)
        ModelOverlay.line(result.centreOfMass, Vec3(result.centreOfMass.x, floor, result.centreOfMass.z), width: width, into: &mesh)
        for index in result.support.indices where result.support.count > 1 {
            ModelOverlay.line(result.support[index], result.support[(index + 1) % result.support.count], width: width * 1.5, into: &mesh)
        }
        return EditorOverlay(mesh: mesh, color: result.stands ? RGBA(0.35, 0.85, 0.5) : RGBA(1, 0.35, 0.3), onTop: true)
    }
}
