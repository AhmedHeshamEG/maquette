import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Two fingers always move the view (U5, CONTEXT §10.11: "two fingers on the stage always navigate"): the point under
/// them stays under them while they pan, a pinch zooms toward them, a twist turns the view. On a selected overlay pinch
/// and twist size and turn it; in the Director view they truck, dolly and roll the shot camera; while performing they
/// turn and size what you perform.
extension StageGestures {
    /// The world point under the fingers when they landed (what stays under them), on the plane facing the view.
    func navigationAnchor(at point: CGPoint, stage: StageView) -> (point: Vec3, normal: Vec3)? {
        let viewpoint = stage.viewpoint
        let normal = (viewpoint.eye - viewpoint.target).normalized
        if let (_, hit) = stage.pickObject(at: point) { return (hit.point, normal) }
        guard let ray = stage.worldRay(at: point),
              let hit = GuideSurface.plane(origin: viewpoint.target, normal: normal).intersect(ray) else { return (viewpoint.target, normal) }
        return (hit.point, normal)
    }

    @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let stage else { return }
        let translation = recognizer.translation(in: stage)
        recognizer.setTranslation(.zero, in: stage)
        if operatesCamera, let editor {
            if recognizer.state == .began { panKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled { editor.endGesture() }
            // Truck and pedestal in the camera's own frame.
            let step = 0.01 * navigationSpeed
            editor.moveCamera(local: Vec3(-Double(translation.x) * step, Double(translation.y) * step, 0), gesture: panKey)
            return
        }
        guard recognizer.state == .changed || recognizer.state == .began else { return }
        let point = recognizer.location(in: stage)
        if recognizer.state == .began { panAnchor = navigationAnchor(at: point, stage: stage) }
        // The grabbed point stays under the fingers, whatever its depth (U5: one feel).
        let previous = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
        guard let anchor = panAnchor, let from = stage.worldRay(at: previous), let to = stage.worldRay(at: point) else { return }
        let plane = GuideSurface.plane(origin: anchor.point, normal: anchor.normal)
        guard let a = plane.intersect(from)?.point, let b = plane.intersect(to)?.point, (a - b).length < 50 else { return }
        var viewpoint = stage.viewpoint
        viewpoint.target += a - b
        stage.setViewpoint(viewpoint)
    }

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        defer { recognizer.scale = 1 }
        guard let editor, let stage else { return }
        if isRecordingPerform {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.scale])
            case .changed: editor.performScale(by: Double(recognizer.scale))
            default: editor.performTouchEnded()
            }
            return
        }
        if recognizer.state == .began { pinchKey = UUID().uuidString }
        let ended = recognizer.state == .ended || recognizer.state == .cancelled
        if let overlay = editor.selectedOverlay {
            if ended { editor.endGesture() } else { editor.scaleOverlay(overlay, by: Double(recognizer.scale), gesture: pinchKey) }
        } else if operatesCamera {
            // Dolly: pinching out moves the camera forward.
            if ended { editor.endGesture() } else {
                editor.moveCamera(local: Vec3(0, 0, -Double(recognizer.scale - 1) * 3 * navigationSpeed), gesture: pinchKey)
            }
        } else if recognizer.state == .changed || recognizer.state == .began {
            // Toward the fingers: the point between them stays where it is on screen (U5).
            if recognizer.state == .began { pinchAnchor = navigationAnchor(at: recognizer.location(in: stage), stage: stage)?.point }
            let scale = pow(Double(max(recognizer.scale, 0.01)), navigationSpeed)
            var viewpoint = stage.viewpoint
            viewpoint.distance /= scale
            if let anchor = pinchAnchor { viewpoint.target += (anchor - viewpoint.target) * (1 - 1 / scale) }
            stage.setViewpoint(viewpoint)
        }
    }

    @objc func handleTwist(_ recognizer: UIRotationGestureRecognizer) {
        guard let editor else { return }
        defer { recognizer.rotation = 0 }
        if isRecordingPerform {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.rotation])
            case .changed: editor.performRotate(by: -Double(recognizer.rotation))
            default: editor.performTouchEnded()
            }
            return
        }
        if recognizer.state == .began { twistKey = UUID().uuidString }
        let ended = recognizer.state == .ended || recognizer.state == .cancelled
        if let overlay = editor.selectedOverlay {
            if ended { editor.endGesture() } else { editor.rotateOverlay(overlay, by: -Double(recognizer.rotation), gesture: twistKey) }
        } else if operatesCamera {
            if ended { editor.endGesture() } else { editor.rollCamera(by: Double(recognizer.rotation), gesture: twistKey) }
        } else if let stage, recognizer.state == .changed {
            var viewpoint = stage.viewpoint
            viewpoint.yaw += Double(recognizer.rotation) * 180 / .pi
            stage.setViewpoint(viewpoint)
        }
    }
}
