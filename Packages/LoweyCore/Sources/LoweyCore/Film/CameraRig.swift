import Foundation

public extension PropertyKey {
    /// What a camera is mounted on (F1): a dolly, a crane, an orbit or held in the hand. Its moves are keyed numbers, so a
    /// crane up is two keys of one slider and the timeline shows it like any motion.
    static let rig: PropertyKey = "rig"
    /// Dolly: metres along the track (the way the camera faces, level), forward positive.
    static let rigTravel: PropertyKey = "rigTravel"
    /// Crane and orbit: metres up from where the camera stands.
    static let rigLift: PropertyKey = "rigLift"
    /// Crane: degrees the arm swings around its base; orbit: degrees around what it watches (left positive, from above).
    static let rigSwing: PropertyKey = "rigSwing"
    /// Crane: the arm's length in metres (its base stands behind the camera).
    static let rigArm: PropertyKey = "rigArm"
    /// Handheld: how much the hands shake, 0…1 (any rig can add it).
    static let rigShake: PropertyKey = "rigShake"
    /// The thing the lens keeps sharp (F1): it follows the thing as it moves; keyed, the focus pulls to the next one.
    static let focusOn: PropertyKey = "focusOn"
}

public extension PropertySpec {
    static let film: [PropertyKey: PropertySpec] = [
        .sensor: PropertySpec(type: .enumeration, animatable: false, label: "Camera body"),
        .rig: PropertySpec(type: .enumeration, animatable: false, label: "Rig"),
        .rigTravel: PropertySpec(type: .float, animatable: true, label: "Dolly"),
        .rigLift: PropertySpec(type: .float, animatable: true, label: "Lift"),
        .rigSwing: PropertySpec(type: .float, animatable: true, label: "Swing"),
        .rigArm: PropertySpec(type: .float, animatable: false, label: "Arm"),
        .rigShake: PropertySpec(type: .float, animatable: true, label: "Handheld"),
        .focusOn: PropertySpec(type: .string, animatable: true, label: "Focus on"),
        .lightWidth: PropertySpec(type: .float, animatable: true, label: "Width"),
        .lightHeight: PropertySpec(type: .float, animatable: true, label: "Height")
    ]
}

/// What a camera rides (F1). Moves are offsets from where the camera is keyed, so a rig sits on top of any camera move.
public enum CameraRig: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, dolly, crane, orbit, handheld

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "On a tripod"
        case .dolly: "Dolly"
        case .crane: "Crane"
        case .orbit: "Orbit"
        case .handheld: "Handheld"
        }
    }

    /// The numbers its panel offers, in order.
    public var controls: [PropertyKey] {
        switch self {
        case .none: []
        case .dolly: [.rigTravel, .rigShake]
        case .crane: [.rigLift, .rigSwing, .rigArm, .rigShake]
        case .orbit: [.rigSwing, .rigLift, .rigShake]
        case .handheld: [.rigShake]
        }
    }

    public static func of(_ camera: SceneObject) -> CameraRig {
        camera[.rig]?.stringValue.flatMap(CameraRig.init(rawValue:)) ?? .none
    }

    static let defaultArm = 3.0
    static let defaultShake = 0.5

    /// Where the camera is and which way it looks on the rig, from where it stands (`world`) and what it watches.
    /// `aim` is the point a crane and an orbit keep in the frame.
    public static func place(_ camera: SceneObject, world: Transform, aim: Vec3, time: Double, shaking: Bool = true) -> Transform {
        let rig = of(camera)
        var result = world
        let forward = world.rotation.act(Vec3(0, 0, -1))
        var level = Vec3(forward.x, 0, forward.z)
        level = level.length > 1e-6 ? level.normalized : Vec3(0, 0, -1)
        let value = { (key: PropertyKey) in camera[key]?.floatValue ?? 0 }
        switch rig {
        case .none, .handheld:
            break
        case .dolly:
            result.position = world.position + level * value(.rigTravel)
        case .crane:
            let arm = camera[.rigArm]?.floatValue ?? defaultArm
            let base = world.position - level * arm
            let swing = Quat(angle: value(.rigSwing) * .pi / 180, axis: .unitY)
            result.position = base + swing.act(world.position - base) + Vec3(0, value(.rigLift), 0)
            result.rotation = BehaviorEvaluator.facing(aim - result.position, cameraStyle: true)
        case .orbit:
            let swing = Quat(angle: value(.rigSwing) * .pi / 180, axis: .unitY)
            result.position = aim + swing.act(world.position - aim) + Vec3(0, value(.rigLift), 0)
            result.rotation = BehaviorEvaluator.facing(aim - result.position, cameraStyle: true)
        }
        if shaking { result = shaken(camera, result, time: time) }
        return result
    }

    /// The hands on top of everything else (after the camera has turned to what it watches).
    static func shaken(_ camera: SceneObject, _ pose: Transform, time: Double) -> Transform {
        let shake = camera[.rigShake]?.floatValue ?? (of(camera) == .handheld ? defaultShake : 0)
        return shake > 0 ? handheld(pose, amount: min(shake, 1), time: time, seed: Noise.seed(camera.id.raw)) : pose
    }

    /// A person holding the camera: slow breathing drift, a little sway, small fast corrections. Smooth noise on each
    /// axis, the same every time it plays (seeded by the camera).
    static func handheld(_ pose: Transform, amount: Double, time: Double, seed: UInt64) -> Transform {
        func wander(_ salt: UInt64, _ rate: Double) -> Double { Noise.fractal(time * rate, seed: seed &+ salt) }
        let degrees = Vec3(wander(1, 0.9) * 1.1, wander(2, 0.7) * 1.4, wander(3, 1.1) * 0.6) * amount
        let turn = Quat(eulerDegrees: degrees)
        let local = Vec3(wander(4, 0.5) * 0.012, wander(5, 0.8) * 0.009, wander(6, 0.4) * 0.006) * amount
        var result = pose
        result.rotation = (pose.rotation * turn).normalized
        result.position = pose.position + pose.rotation.act(local)
        return result
    }

    static func anyone(in scene: Scene) -> Bool {
        scene.objects.values.contains { $0.kind == .camera && ($0[.rig] != nil || $0[.rigShake] != nil) }
    }

    /// Every rigged camera onto its rig: the Animator's step before looks and focus.
    static func apply(to state: inout Animator.Posed, time: Double) {
        each(in: &state) { camera, world, state in
            let aim = camera[.lookAt]?.stringValue.map(ObjectID.init(raw:)).flatMap { LookAt.aimPoint(of: $0, in: state) }
                ?? world.position + world.rotation.act(Vec3(0, 0, -1)) * (camera[.focusDistance]?.floatValue ?? 5)
            return place(camera, world: world, aim: aim, time: time, shaking: false)
        }
    }

    /// The hands, after looks.
    static func shake(_ state: inout Animator.Posed, time: Double) {
        each(in: &state) { camera, world, _ in shaken(camera, world, time: time) }
    }

    private static func each(in state: inout Animator.Posed, _ placed: (SceneObject, Transform, Animator.Posed) -> Transform) {
        for id in state.scene.objects.keys.sorted() {
            guard let camera = state.scene.objects[id], camera.kind == .camera, camera[.rig] != nil || camera[.rigShake] != nil else { continue }
            let world = state.scene.worldTransform(of: id)
            let pose = placed(camera, world, state)
            var object = camera
            object.transform = Transform.relative(world: Transform(position: pose.position, rotation: pose.rotation, scale: world.scale),
                                                  toParent: camera.parent.map { state.scene.worldTransform(of: $0) } ?? .identity)
            state.scene.objects[id] = object
            state.animated.insert(id)
        }
    }
}
