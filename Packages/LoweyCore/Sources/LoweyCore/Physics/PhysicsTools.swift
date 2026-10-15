import Foundation

/// Settle and "does it stand": two quick questions answered with the same physics.
public enum PhysicsTools {
    /// Where a thing comes to rest when let go from where it is: onto its natural resting face, on the ground or on
    /// what's under it. `meshes` holds the local meshes of the thing and of everything it may land on. Nil when it has
    /// nothing to fall onto or no shape.
    public static func settle(_ id: ObjectID, in scene: Scene, meshes: [ObjectID: MeshData], ground: Bool = true) -> Transform? {
        guard let object = scene.objects[id], let mesh = meshes[id] else { return nil }
        let world = scene.worldTransform(of: id)
        guard let shape = BodyShape.make(kind: object.kind, mesh: mesh, scale: world.scale, motion: .falls),
              let physicsWorld = PhysicsWorld(capacity: meshes.count + 4, gravity: 9.81) else { return nil }
        if ground {
            _ = physicsWorld.add(PhysicsWorld.BodySpec(shape: BodyShape(kind: .box(half: Vec3(500, 1, 500))), position: Vec3(0, -1, 0), rotation: .identity,
                                                       motion: .stays, density: 1000, friction: 0.8, bounce: 0))
        }
        let moving = Set(scene.subtree(of: id))
        for (other, otherMesh) in meshes where !moving.contains(other) && scene.isEffectivelyVisible(other) {
            let place = scene.worldTransform(of: other)
            let points = otherMesh.positions.map { Vec3($0).scaled(by: place.scale) }
            _ = physicsWorld.add(PhysicsWorld.BodySpec(shape: BodyShape(kind: .mesh(points: points, indices: otherMesh.indices)), position: place.position,
                                                       rotation: place.rotation, motion: .stays, density: 1000, friction: 0.8, bounce: 0))
        }
        let material = object.physics?.material ?? .wood
        let rotation = world.rotation.normalized
        guard let body = physicsWorld.add(PhysicsWorld.BodySpec(shape: shape, position: world.position + rotation.act(shape.offset), rotation: rotation,
                                                                motion: .falls, density: material.density, friction: 0.9, bounce: 0,
                                                                linearDamping: 0.3, angularDamping: 0.5)) else { return nil }
        for _ in 0 ..< 600 {
            physicsWorld.step(1.0 / 60, substeps: 1)
            if !physicsWorld.isAwake(body) { break }
        }
        let (position, turned) = physicsWorld.transform(of: body)
        return Transform(position: position - turned.act(shape.offset), rotation: turned, scale: world.scale)
    }

    public struct Stability: Hashable, Sendable {
        public var stands: Bool
        /// World space.
        public var centreOfMass: Vec3
        /// The outline it stands on, at floor height, counter-clockwise in (x, z).
        public var support: [Vec3]
        /// How far the centre of mass is inside its outline (negative: outside, it tips that far over).
        public var margin: Double
        /// Kg, from each thing's material (wood when it isn't real).
        public var mass: Double
    }

    /// Does it stand? The centre of mass of the things (their real materials) over the outline of where they touch
    /// what's under them.
    public static func stability(of ids: [ObjectID], in scene: Scene, meshes: [ObjectID: MeshData]) -> Stability? {
        guard let world = PhysicsWorld(capacity: ids.count * 8 + 8, gravity: 0) else { return nil }
        var total = 0.0
        var weighted = Vec3.zero
        var points: [Vec3] = []
        for id in ids {
            for part in scene.subtree(of: id) {
                guard let object = scene.objects[part], let mesh = meshes[part] else { continue }
                let place = scene.worldTransform(of: part)
                points += mesh.positions.map { place.apply(to: Vec3($0)) }
                guard let shape = BodyShape.make(kind: object.kind, mesh: mesh, scale: place.scale, motion: .falls) else { continue }
                let material = (object.physics ?? scene.objects[id]?.physics)?.material ?? .wood
                let rotation = place.rotation.normalized
                guard let body = world.add(PhysicsWorld.BodySpec(shape: shape, position: place.position + rotation.act(shape.offset), rotation: rotation,
                                                                 motion: .falls, density: material.density, mass: object.physics?.mass,
                                                                 friction: 0.5, bounce: 0)) else { continue }
                let mass = world.mass(of: body)
                total += mass
                weighted += world.centerOfMass(of: body) * mass
            }
        }
        guard total > 0, let lowest = points.map(\.y).min() else { return nil }
        let centre = weighted / total
        let contact = points.filter { $0.y <= lowest + 0.003 }.map { Vec3($0.x, lowest, $0.z) }
        let outline = Outline2D.hull(contact)
        let margin = Outline2D.margin(of: centre, in: outline)
        return Stability(stands: margin > 0, centreOfMass: centre, support: outline, margin: margin, mass: total)
    }
}

/// Convex outlines on the ground plane, as (x, z).
enum Outline2D {
    /// Andrew's monotone chain, counter-clockwise in (x, z).
    static func hull(_ points: [Vec3]) -> [Vec3] {
        guard let height = points.first?.y else { return [] }
        var unique = Set<SIMD2<Double>>()
        for point in points {
            let x: Double = (point.x * 1e5).rounded() / 1e5
            let z: Double = (point.z * 1e5).rounded() / 1e5
            unique.insert(SIMD2<Double>(x, z))
        }
        let sorted = unique.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted.map { Vec3($0.x, height, $0.y) } }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [SIMD2<Double>] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [SIMD2<Double>] = []
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        return (lower.dropLast() + upper.dropLast()).map { Vec3($0.x, height, $0.y) }
    }

    /// How far inside a convex outline a point is (by x, z): the distance to the nearest edge's line, negative once
    /// it's beyond one. A line or a point holds nothing up.
    static func margin(of point: Vec3, in outline: [Vec3]) -> Double {
        guard outline.count >= 3 else {
            let nearest = outline.map { Vec3($0.x - point.x, 0, $0.z - point.z).length }.min() ?? .infinity
            return -max(nearest, 1e-6)
        }
        var result = Double.infinity
        for index in outline.indices {
            let a = outline[index]
            let b = outline[(index + 1) % outline.count]
            let edge = SIMD2<Double>(b.x - a.x, b.z - a.z)
            let length = (edge.x * edge.x + edge.y * edge.y).squareRoot()
            guard length > 1e-12 else { continue }
            let offset = SIMD2<Double>(point.x - a.x, point.z - a.z)
            result = min(result, (edge.x * offset.y - edge.y * offset.x) / length)
        }
        return result
    }
}
