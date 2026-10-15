import Foundation

// MARK: - Physics (P1)

/// `{"do": "physics", "op": …}`: real things, the scene's gravity and wind, joints, forces, fluids, Keep it, Settle,
/// "does it stand" and the real sun, each one undo step. Points and directions are in the scene's metres.
extension ScriptState {
    static let physicsOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "real": { try $0.physicsReal($1) },
        "unreal": { try $0.physicsUnreal($1) },
        "scene": { try $0.physicsScene($1) },
        "joint": { try $0.physicsJoint($1) },
        "unjoin": { try $0.physicsUnjoin($1) },
        "force": { try $0.physicsForce($1) },
        "fluid": { try $0.physicsFluid($1) },
        "keep": { try $0.physicsKeep($1) },
        "settle": { try $0.physicsSettle($1) },
        "stand": { try $0.physicsStand($1) },
        "sun": { try $0.physicsSun($1) }
    ]

    mutating func physics(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.physicsOps[op] else {
            throw fail("physics needs “op”: \(Self.physicsOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    /// A thing's local mesh: the app's (placed models too), else what Core makes itself.
    func physicsMesh(_ object: SceneObject) -> MeshData? {
        context.mesh(object) ?? SceneExport.localMesh(of: object, look: document.effectiveLook)
    }

    var scenePhysics: ScenePhysics { scene.physics ?? ScenePhysics() }

    mutating func physicsReal(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        guard !ids.isEmpty else { throw fail("real needs “target”") }
        var commands: [EditCommand] = []
        for id in ids {
            var physics = scene.objects[id]?.physics ?? ObjectPhysics()
            try physicsWords(action, into: &physics)
            physicsNumbers(action, into: &physics)
            commands.append(.setPhysics(id, physics))
        }
        let names = ids.compactMap { scene.objects[$0]?.name }.joined(separator: ", ")
        try run(.batch("Real", commands), label: "Real: \(names)")
    }

    /// The material and how it moves, by name.
    func physicsWords(_ action: JSONValue, into physics: inout ObjectPhysics) throws {
        if let name = string(action, "material") {
            guard let material = PhysicsMaterial(rawValue: name.lowercased()) else {
                throw fail("unknown material “\(name)” (\(PhysicsMaterial.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            physics.material = material
        }
        if let motion = string(action, "motion") {
            guard let value = ObjectPhysics.Motion(rawValue: motion) else { throw fail("“motion” is falls, stays or follows") }
            physics.motion = value
        }
    }

    /// The numbers one step deeper.
    func physicsNumbers(_ action: JSONValue, into physics: inout ObjectPhysics) {
        if let mass = number(action, "mass") { physics.mass = mass }
        if let friction = number(action, "friction") { physics.friction = friction }
        if let bounce = number(action, "bounce") { physics.bounce = bounce }
        if let speed = vec3(action["speed"]) { physics.startSpeed = speed }
        if let spin = vec3(action["spin"]) { physics.startSpin = spin }
        if let breaks = bool(action, "breaks") { physics.breaks = breaks }
        if let stiffness = number(action, "stiffness") { physics.stiffness = min(max(stiffness, 0), 1) }
        if let hangs = bool(action, "hangs") { physics.hangs = hangs }
    }

    mutating func physicsUnreal(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        try run(.batch("Not real", ids.map { .setPhysics($0, nil) }), label: "Not real: \(ids.compactMap { scene.objects[$0]?.name }.joined(separator: ", "))")
    }

    mutating func physicsScene(_ action: JSONValue) throws {
        var settings = scenePhysics
        if let gravity = string(action, "gravity") {
            guard let preset = GravityPreset(rawValue: gravity) else {
                throw fail("“gravity” is \(GravityPreset.allCases.map(\.rawValue).joined(separator: ", ")), or a number in m/s²")
            }
            settings.gravity = preset
            settings.customGravity = nil
        } else if let value = number(action, "gravity") {
            settings.customGravity = value
        }
        if let wind = action["wind"] {
            settings.windSpeed = wind["speed"]?.numberValue ?? settings.windSpeed
            settings.windHeading = wind["heading"]?.numberValue ?? settings.windHeading
            settings.gusts = wind["gusts"]?.numberValue ?? settings.gusts
        }
        if let ground = bool(action, "ground") { settings.ground = ground }
        if let start = number(action, "start") { settings.start = max(start, 0) }
        try run(.setScenePhysics(settings), label: "Physics: \(settings.gravity.title), wind \(Self.short(settings.windSpeed)) m/s")
    }

    mutating func physicsJoint(_ action: JSONValue) throws {
        guard let kindName = string(action, "kind"), let kind = PhysicsJoint.Kind(rawValue: kindName) else {
            throw fail("joint needs “kind”: \(PhysicsJoint.Kind.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let first = try target(action["first"] ?? action["target"])
        let second = try action["second"].map { try target($0) }
        let firstWorld = scene.worldTransform(of: first)
        let anchorWorld = try point(action["anchor"]) ?? firstWorld.position
        var joint = PhysicsJoint(id: string(action, "id") ?? context.ids.next(ObjectID.self).raw, kind: kind, first: first, second: second,
                                 anchor: firstWorld.inverseApply(to: anchorWorld))
        if let axis = vec3(action["axis"]) { joint.axis = firstWorld.inverseApplyDirection(axis).normalized }
        if let other = try point(action["to"]) {
            joint.otherAnchor = second.map { scene.worldTransform(of: $0).inverseApply(to: other) } ?? other
        }
        if let limits = action["limits"]?.arrayValue?.compactMap(\.numberValue), limits.count == 2, limits[0] <= limits[1] {
            joint.limits = limits[0] ... limits[1]
        }
        joint.motorSpeed = number(action, "motor")
        joint.motorStrength = number(action, "strength")
        joint.springiness = number(action, "springiness")
        joint.length = number(action, "length")
        joint.gears = action["gears"]?.arrayValue?.compactMap(\.stringValue)
        joint.ratio = number(action, "ratio")
        var settings = scenePhysics
        settings.joints.removeAll { $0.id == joint.id }
        settings.joints.append(joint)
        try run(.setScenePhysics(settings), label: "\(kind.title) “\(joint.id)”")
    }

    mutating func physicsUnjoin(_ action: JSONValue) throws {
        guard let id = string(action, "id") else { throw fail("unjoin needs the joint's “id”") }
        var settings = scenePhysics
        settings.joints.removeAll { $0.id == id }
        try run(.setScenePhysics(settings), label: "Unjoined “\(id)”")
    }

    mutating func physicsForce(_ action: JSONValue) throws {
        guard let kind = string(action, "kind").flatMap(ForceRecipe.Kind.init(rawValue:)) else {
            throw fail("force needs “kind”: fan, pull or whirl")
        }
        let recipe = ForceRecipe(kind: kind, strength: number(action, "strength"), reach: number(action, "reach") ?? 3)
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: kind.title), kind: .force(recipe))
        object.transform.position = try point(action["at"]) ?? context.focus
        if let aim = vec3(action["aim"]), aim.length > 1e-9 { object.transform.rotation = Quat.rotation(from: Vec3(0, 0, -1), to: aim.normalized) }
        try insert(object, action: action, verb: "Add")
    }

    mutating func physicsFluid(_ action: JSONValue) throws {
        guard let kind = string(action, "kind").flatMap(FluidRecipe.Kind.init(rawValue:)) else {
            throw fail("fluid needs “kind”: pour, splash, smoke or fire")
        }
        let recipe = FluidRecipe(kind: kind, box: vec3(action["box"]), amount: number(action, "amount"), duration: number(action, "duration") ?? 3,
                                 color: string(action, "color").flatMap(RGBA.init(hex:)), width: number(action, "width") ?? 0.04)
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: kind.title), kind: .fluid(recipe))
        object.transform.position = try point(action["at"]) ?? context.focus
        try insert(object, action: action, verb: "Add")
    }

    mutating func physicsKeep(_: JSONValue) throws {
        let current = document
        guard let input = PhysicsInput.make(current, mesh: physicsMesh), let frames = PhysicsSimulator.run(input) else {
            throw fail("nothing in this scene is real")
        }
        guard let command = PhysicsKeep.keep(frames, in: current, ids: &context.ids) else { throw fail("nothing moved") }
        try run(command, label: "Keep it: the run is keys now")
    }

    mutating func physicsSettle(_ action: JSONValue) throws {
        let id = try target(action["target"])
        var meshes: [ObjectID: MeshData] = [:]
        for (other, object) in scene.objects {
            if let mesh = physicsMesh(object) { meshes[other] = mesh }
        }
        guard let object = scene.objects[id], let settled = PhysicsTools.settle(id, in: scene, meshes: meshes, ground: scenePhysics.ground) else {
            throw fail("“\(scene.objects[id]?.name ?? "It")” has no shape to settle")
        }
        let parent = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
        let local = Transform.relative(world: settled, toParent: parent)
        try run(.setProperties([PropertyChange(object: id, key: .position, value: .vec3(local.position)),
                                PropertyChange(object: id, key: .rotation, value: .quat(local.rotation))]), label: "Settle “\(object.name)”")
    }

    mutating func physicsStand(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        var meshes: [ObjectID: MeshData] = [:]
        for id in ids.flatMap({ scene.subtree(of: $0) }) {
            if let object = scene.objects[id], let mesh = physicsMesh(object) { meshes[id] = mesh }
        }
        guard let result = PhysicsTools.stability(of: ids, in: scene, meshes: meshes) else { throw fail("nothing there to stand") }
        let weight = "\(Self.short(result.mass)) kg"
        report.append(result.stands ? "It stands: its centre of mass is \(Self.short(result.margin * 100)) cm inside its footprint (\(weight))"
            : "It tips over: its centre of mass is \(Self.short(-result.margin * 100)) cm past its footprint (\(weight))")
    }

    mutating func physicsSun(_ action: JSONValue) throws {
        var look = document.effectiveLook
        if bool(action, "off") == true {
            look.lighting.realSun = nil
        } else {
            var sun = look.lighting.realSun ?? RealSun.places[0]
            if let place = string(action, "place") {
                guard let known = RealSun.places.first(where: { $0.place.lowercased() == place.lowercased() }) else {
                    let places = RealSun.places.map(\.place).joined(separator: ", ")
                    throw fail("unknown place “\(place)”: give “latitude”, “longitude” and “utcOffset”, or one of \(places)")
                }
                (sun.place, sun.latitude, sun.longitude, sun.utcOffset) = (known.place, known.latitude, known.longitude, known.utcOffset)
            }
            sun.latitude = number(action, "latitude") ?? sun.latitude
            sun.longitude = number(action, "longitude") ?? sun.longitude
            sun.utcOffset = number(action, "utcOffset") ?? sun.utcOffset
            if let date = string(action, "date") {
                let parts = date.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { throw fail("“date” is written 2026-06-21") }
                (sun.year, sun.month, sun.day) = (parts[0], parts[1], parts[2])
            }
            sun.hour = number(action, "hour") ?? sun.hour
            sun.north = number(action, "north") ?? sun.north
            if let study = action["study"]?.arrayValue?.compactMap(\.numberValue), study.count == 2, study[0] < study[1] {
                sun.study = study[0] ... study[1]
            } else if bool(action, "study") == false {
                sun.study = nil
            }
            look.lighting.realSun = sun
        }
        let scope: LookScope = scene.look == nil ? .project : .scene
        try run(.setLook(look, scope: scope), label: look.lighting.realSun.map { "The real sun over \($0.place)" } ?? "The sun is placed by hand")
    }
}
