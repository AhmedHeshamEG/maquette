import Foundation

/// Wind, fans, pulls and whirls on everything real, and the fluids stepped beside the bodies they meet.
extension PhysicsSimulator {
    /// Air density (kg/m³).
    static let air = 1.2

    func applyForces(at time: Double) {
        let wind = input.settings.wind(at: time)
        let forces = input.forces.compactMap { id -> (ForceRecipe, Transform)? in
            guard case let .force(recipe) = input.scene.objects[id]?.kind else { return nil }
            return (recipe, place(of: id))
        }
        guard wind != .zero || !forces.isEmpty else { return }
        for rigid in rigids where rigid.mass > 0 {
            push(rigid.body, mass: rigid.mass, area: rigid.area, wind: wind, forces: forces)
        }
        for ragdoll in ragdolls {
            for part in ragdoll.parts {
                push(part.body, mass: part.mass, area: pow(part.mass / 1000, 2.0 / 3.0), wind: wind, forces: forces)
            }
        }
        for state in breaks {
            for body in state.bodies {
                let mass = world.mass(of: body)
                push(body, mass: mass, area: pow(mass / max(state.density, 1), 2.0 / 3.0), wind: wind, forces: forces)
            }
        }
        for soft in softs {
            // Fans blow cloth as wind does.
            var air = wind
            let centre = softCentre(soft)
            for (recipe, place) in forces where recipe.kind == .fan {
                air += recipe.acceleration(at: centre, velocity: .zero, place: place) / 1.2
            }
            if air != .zero { world.blowSoft(soft.body, wind: air, dt: dt) }
        }
    }

    private func push(_ body: Int32, mass: Double, area: Double, wind: Vec3, forces: [(ForceRecipe, Transform)]) {
        let velocity = world.velocity(of: body).linear
        let centre = world.centerOfMass(of: body)
        var force = Vec3.zero
        if wind != .zero {
            // Drag: ½ ρ C A |v| v with the air moving at the wind's speed (C ≈ 1 for a blunt thing).
            let relative = wind - velocity
            force += relative * (0.5 * Self.air * area * relative.length)
        }
        for (recipe, place) in forces {
            let acceleration = recipe.acceleration(at: centre, velocity: velocity, place: place)
            // A fan pushes through the air, so light things feel it more than heavy ones; pulls act on mass itself.
            force += recipe.kind == .fan ? acceleration * (0.5 * Self.air * area * 4) : acceleration * mass
        }
        if force.length > 1e-9 { world.push(body, force: force) }
    }

    private func softCentre(_ soft: SoftState) -> Vec3 {
        let vertices = world.softVertices(of: soft.body, count: soft.count)
        guard soft.count >= 1 else { return .zero }
        var sum = Vec3.zero
        for index in 0 ..< soft.count {
            sum += Vec3(Double(vertices[index * 3]), Double(vertices[index * 3 + 1]), Double(vertices[index * 3 + 2]))
        }
        return sum / Double(soft.count)
    }

    // MARK: Fluids

    func addFluids() {
        for id in input.fluids {
            guard let object = input.scene.objects[id], case let .fluid(recipe) = object.kind else {
                fluidSlots.append((nil, nil))
                continue
            }
            let place = input.scene.worldTransform(of: id)
            let colliders = fluidColliders(around: FluidBox.make(recipe, at: place.position, ground: input.settings.ground), fine: recipe.kind.isLiquid)
            if recipe.kind.isLiquid {
                liquids.append(LiquidSolver(recipe: recipe, emitter: place, colliders: colliders, ground: input.settings.ground,
                                            gravity: input.settings.acceleration, fps: input.fps))
                fluidSlots.append((liquids.count - 1, nil))
            } else {
                smokes.append(SmokeSolver(recipe: recipe, emitter: place, colliders: colliders, fps: input.fps))
                fluidSlots.append((nil, smokes.count - 1))
            }
        }
    }

    /// Every surface inside a fluid's box, as a distance field in its own space; moving ones are followed frame by frame.
    private func fluidColliders(around box: Bounds, fine: Bool) -> [FluidCollider] {
        var result: [FluidCollider] = []
        for (id, mesh) in input.meshes.sorted(by: { $0.key < $1.key }) {
            guard let object = input.scene.objects[id], object.kind.hasSurface, input.scene.isEffectivelyVisible(id) else { continue }
            let world = input.scene.worldTransform(of: id)
            guard let bounds = mesh.bounds?.transformed(by: world), bounds.intersects(box) else { continue }
            let scaled = MeshData(positions: mesh.positions.map { $0 * world.scale.map(abs).floats }, indices: mesh.indices)
            // Water needs walls finer than its drops; smoke only needs the rough shape.
            let cell = fine ? 0.003 : max(min(box.size.minComponent / 48, 0.02), 0.004)
            guard let field = DistanceField.make(scaled, cell: cell) else { continue }
            result.append(FluidCollider(object: id, field: field, start: Transform(position: world.position, rotation: world.rotation)))
        }
        return result
    }

    /// Where a collider is now: the rigid body that carries it, else where it started.
    func colliderPlace(_ collider: FluidCollider) -> Transform {
        var current: ObjectID? = collider.object
        while let id = current {
            if let rigid = rigids.first(where: { $0.id == id }) {
                let (position, rotation) = world.transform(of: rigid.body)
                let thing = Transform(position: position - rotation.act(rigid.offset), rotation: rotation)
                if id == collider.object { return thing }
                let startThing = input.scene.worldTransform(of: id)
                let relative = Transform.relative(world: collider.start, toParent: Transform(position: startThing.position, rotation: startThing.rotation))
                return thing * relative
            }
            current = input.scene.objects[id]?.parent
        }
        return collider.start
    }

    func stepFluids(at time: Double) {
        let wind = input.settings.wind(at: time)
        let forces = input.forces.compactMap { id -> (ForceRecipe, Transform)? in
            guard case let .force(recipe) = input.scene.objects[id]?.kind else { return nil }
            return (recipe, place(of: id))
        }
        for index in liquids.indices {
            let places = liquids[index].colliders.map(colliderPlace)
            liquids[index].step(dt, time: time - input.start, colliders: places, forces: forces)
        }
        for index in smokes.indices {
            let places = smokes[index].colliders.map(colliderPlace)
            smokes[index].step(dt, time: time - input.start, colliders: places, wind: wind)
        }
    }

    func fluidLooks() -> [PhysicsFrames.FluidLook] {
        fluidSlots.map { slot in
            if let liquid = slot.liquid { return liquids[liquid].look() }
            if let smoke = slot.smoke { return smokes[smoke].look() }
            return PhysicsFrames.FluidLook()
        }
    }
}

/// A surface fluids meet: its distance field in its own (unturned, unmoved, scaled) space and where it started.
struct FluidCollider {
    var object: ObjectID
    var field: DistanceField
    var start: Transform
}

/// The box a fluid lives in: a stream hangs from just above its tap; smoke and fire rise from their source.
enum FluidBox {
    static func make(_ recipe: FluidRecipe, at point: Vec3, ground: Bool) -> Bounds {
        let size = recipe.box
        let bottom: Double = recipe.kind.isLiquid ? point.y + size.y * 0.1 - size.y : point.y - 0.05
        let floor = ground ? max(bottom, 0) : bottom
        let top = recipe.kind.isLiquid ? point.y + size.y * 0.1 : floor + size.y
        return Bounds(min: Vec3(point.x - size.x / 2, floor, point.z - size.z / 2),
                      max: Vec3(point.x + size.x / 2, max(top, floor + 0.1), point.z + size.z / 2))
    }
}
