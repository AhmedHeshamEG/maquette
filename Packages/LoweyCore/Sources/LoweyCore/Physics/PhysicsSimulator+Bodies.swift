import Foundation

extension PhysicsSimulator {
    /// One real thing: a ragdoll when it's rigged and falls, cloth or jelly by its material, else a rigid body.
    func addThing(_ id: ObjectID) {
        guard let object = input.scene.objects[id], let physics = object.physics else { return }
        let world = input.scene.worldTransform(of: id)
        if physics.motion == .falls, let skeleton = input.skeletons[id], let pose = input.startPoses[id] {
            if addRagdoll(id, skeleton: skeleton, pose: pose, world: world, physics: physics) { return }
        }
        if physics.motion == .falls, physics.material.body != .rigid, let mesh = input.meshes[id] {
            addSoft(id, mesh: mesh, world: world, physics: physics)
            return
        }
        guard let shape = shape(of: id, object: object, world: world, motion: physics.motion) else { return }
        let rotation = world.rotation.normalized
        let mass = physics.mass
        let spec = PhysicsWorld.BodySpec(shape: shape, position: world.position + rotation.act(shape.offset), rotation: rotation,
                                         motion: physics.motion, density: physics.material.density, mass: mass,
                                         friction: physics.effectiveFriction, bounce: physics.effectiveBounce,
                                         linearVelocity: physics.startSpeed ?? .zero, angularVelocity: physics.startSpin ?? .zero)
        guard let body = self.world.add(spec) else { return }
        let realMass = physics.motion == .falls ? self.world.mass(of: body) : 0
        let volume = max(shape.volume, 1e-6)
        var rigid = Rigid(id: id, body: body, offset: shape.offset, mass: realMass, area: pow(volume, 2.0 / 3.0), breakable: nil,
                          lastVelocity: physics.startSpeed ?? .zero)
        if physics.motion == .falls, physics.effectiveBreaks, let mesh = input.meshes[id] {
            rigid.breakable = addBreakable(id, rigidIndex: rigids.count, mesh: mesh, scale: world.scale, physics: physics, volume: volume)
        }
        rigids.append(rigid)
    }

    /// The body shape of a thing: its own mesh, or a group's parts glued.
    func shape(of id: ObjectID, object: SceneObject, world: Transform, motion: ObjectPhysics.Motion) -> BodyShape? {
        if let mesh = input.meshes[id], object.children.isEmpty || object.kind != .group {
            return BodyShape.make(kind: object.kind, mesh: mesh, scale: world.scale, motion: motion)
        }
        let inverse = world.rotation.inverse
        let parts: [(mesh: MeshData, transform: Transform)] = input.scene.subtree(of: id).compactMap { part in
            guard let mesh = input.meshes[part] else { return nil }
            let partWorld = input.scene.worldTransform(of: part)
            // Into the group's turned frame: rotation undone, translation removed, every scale kept.
            let points = mesh.positions.map { position -> SIMD3<Float> in
                let local = inverse.act(partWorld.apply(to: Vec3(position)) - world.position)
                return SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z))
            }
            return (MeshData(positions: points, indices: mesh.indices), .identity)
        }
        if motion != .falls {
            var merged = MeshData()
            for part in parts {
                merged.append(part.mesh)
            }
            guard !merged.isEmpty else { return nil }
            return BodyShape(kind: .mesh(points: merged.positions.map { Vec3($0) }, indices: merged.indices))
        }
        return BodyShape.compound(parts, scale: .one)
    }

    /// Cloth or jelly: the mesh welded and cut fine enough to bend, its vertices sharing the thing's real mass.
    func addSoft(_ id: ObjectID, mesh: MeshData, world: Transform, physics: ObjectPhysics) {
        let jelly = physics.material.body == .jelly
        let size = (mesh.bounds?.size.scaled(by: world.scale.map(abs)).maxComponent) ?? 1
        let prepared = SoftMesh.prepare(mesh, edge: max(size / (jelly ? 10 : 22), 0.01), maxVertices: jelly ? 900 : 1600)
        guard prepared.positions.count >= 3 else { return }
        let vertices = prepared.positions.map { world.apply(to: Vec3($0)) }
        let worldMesh = MeshData(positions: vertices.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }, indices: prepared.indices)
        let total = physics.mass ?? (jelly ? SoftMesh.volume(worldMesh) * physics.material.density : SoftMesh.area(worldMesh) * physics.material.density)
        var masses = Array(repeating: max(total, 1e-4) / Double(vertices.count), count: vertices.count)
        if !jelly, physics.hangs == true {
            for index in SoftMesh.topEdge(vertices) {
                masses[index] = 0
            }
        }
        let stiffness = physics.effectiveStiffness
        let spec = PhysicsWorld.SoftSpec(vertices: vertices, triangles: prepared.indices, masses: masses,
                                         compliance: jelly ? (1 - stiffness) * 2e-3 : 1e-7, bendCompliance: jelly ? 1e-3 : (1 - stiffness) * 0.02 + 1e-5,
                                         pressure: jelly ? 600 + 5000 * stiffness : 0, friction: physics.effectiveFriction, bounce: physics.effectiveBounce)
        guard let body = self.world.addSoft(spec) else { return }
        softTriangles[id] = prepared.indices
        softs.append(SoftState(id: id, body: body, count: vertices.count))
    }

    /// A breakable thing's pieces, cut ahead (they wait until a knock breaks it).
    func addBreakable(_ id: ObjectID, rigidIndex: Int, mesh: MeshData, scale: Vec3, physics: ObjectPhysics, volume: Double) -> Int? {
        let scaled = MeshData(positions: mesh.positions.map { $0 * SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z)) },
                              indices: mesh.indices)
        let count = min(max(Int((volume * 4000).squareRoot()), 6), 18)
        var hasher = StableHasher()
        hasher.add(id.raw)
        let pieces = Shatter.pieces(of: scaled, count: count, seed: hasher.value)
        guard pieces.count > 1 else { return nil }
        breaks.append(BreakState(rigid: rigidIndex, centres: pieces.map(\.centre), pieces: pieces.map(\.mesh), threshold: physics.material.breakingSpeed,
                                 bounce: physics.effectiveBounce, friction: physics.effectiveFriction, density: physics.material.density))
        return breaks.count - 1
    }

    /// A thing breaks when one step changes its speed by more than its material takes.
    func breakWhatBroke() {
        for index in rigids.indices {
            let velocity = world.velocity(of: rigids[index].body)
            defer { rigids[index].lastVelocity = velocity.linear }
            guard let slot = rigids[index].breakable, breaks[slot].bodies.isEmpty,
                  (velocity.linear - rigids[index].lastVelocity).length > breaks[slot].threshold else { continue }
            let (position, rotation) = world.transform(of: rigids[index].body)
            let origin = position - rotation.act(rigids[index].offset)
            let before = rigids[index].lastVelocity
            world.remove(rigids[index].body)
            var bodies: [Int32] = []
            for (piece, centre) in zip(breaks[slot].pieces, breaks[slot].centres) {
                let at = origin + rotation.act(centre)
                let outward = rotation.act(centre).normalized * 0.6
                let spec = PhysicsWorld.BodySpec(shape: BodyShape(kind: .hull(piece.positions.map { Vec3($0) })), position: at, rotation: rotation,
                                                 motion: .falls, density: breaks[slot].density, friction: breaks[slot].friction,
                                                 bounce: breaks[slot].bounce, linearVelocity: before * 0.4 + outward + velocity.linear * 0.6,
                                                 angularVelocity: velocity.angular)
                if let body = world.add(spec) { bodies.append(body) }
            }
            breaks[slot].bodies = bodies
        }
    }

    /// Joints between real things, placed by the first thing's own space at the start.
    func addJoints() {
        var made: [String: Int32] = [:]
        let joints = input.settings.joints
        for joint in joints.sorted(by: { ($0.kind == .gear ? 1 : 0) < ($1.kind == .gear ? 1 : 0) }) {
            guard let a = body(of: joint.first) else { continue }
            let b = joint.second.flatMap { body(of: $0) } ?? -1
            let first = input.scene.worldTransform(of: joint.first)
            let anchor = first.apply(to: joint.anchor)
            let axis = first.applyDirection(joint.axis).normalized
            let other: Vec3 = if let second = joint.second, let point = joint.otherAnchor {
                input.scene.worldTransform(of: second).apply(to: point)
            } else {
                joint.otherAnchor ?? anchor
            }
            var spec = PhysicsWorld.JointSpec(kind: joint.kind.bridgeKind, a: a, b: b, pointA: anchor, pointB: other, axis: axis,
                                              normal: Self.perpendicular(to: axis), limits: nil, motorSpeed: nil, motorStrength: joint.motorStrength)
            switch joint.kind {
            case .hinge:
                spec.limits = joint.limits.map { ($0.lowerBound * .pi / 180) ... ($0.upperBound * .pi / 180) }
                spec.motorSpeed = joint.motorSpeed.map { $0 * .pi / 180 }
            case .slider:
                spec.limits = joint.limits
                spec.motorSpeed = joint.motorSpeed
            case .spring, .rope:
                let rest = joint.length ?? anchor.distance(to: other)
                spec.limits = joint.kind == .rope ? 0 ... rest : rest ... rest
                spec.springFrequency = joint.kind == .rope ? 0 : (joint.springiness ?? 2)
            case .gear:
                guard let gears = joint.gears, gears.count == 2, let one = made[gears[0]], let two = made[gears[1]],
                      let firstHinge = joints.first(where: { $0.id == gears[0] }),
                      let secondHinge = joints.first(where: { $0.id == gears[1] }) else { continue }
                spec.gears = (one, two)
                spec.axis = input.scene.worldTransform(of: firstHinge.first).applyDirection(firstHinge.axis).normalized
                spec.normal = input.scene.worldTransform(of: secondHinge.first).applyDirection(secondHinge.axis).normalized
                spec.ratio = joint.ratio ?? 1
                spec.a = body(of: firstHinge.first) ?? a
                spec.b = body(of: secondHinge.first) ?? b
            case .ball, .glue:
                break
            }
            if let made1 = world.addJoint(spec) { made[joint.id] = made1 }
        }
    }

    func body(of id: ObjectID) -> Int32? {
        if let rigid = rigids.first(where: { $0.id == id }) { return rigid.body }
        if let ragdoll = ragdolls.first(where: { $0.id == id }) { return ragdoll.parts.first?.body }
        // A part of a real group is joined through the group's body.
        var parent = input.scene.objects[id]?.parent
        while let current = parent {
            if let rigid = rigids.first(where: { $0.id == current }) { return rigid.body }
            parent = input.scene.objects[current]?.parent
        }
        return nil
    }

    static func perpendicular(to axis: Vec3) -> Vec3 {
        let helper = abs(axis.y) < 0.9 ? Vec3.unitY : Vec3.unitX
        return axis.cross(helper).normalized
    }
}

extension PhysicsJoint.Kind {
    var bridgeKind: PhysicsWorld.JointKind {
        switch self {
        case .hinge: .hinge
        case .slider: .slider
        case .ball: .ball
        case .glue: .fixed
        case .spring, .rope: .spring
        case .gear: .gear
        }
    }
}
