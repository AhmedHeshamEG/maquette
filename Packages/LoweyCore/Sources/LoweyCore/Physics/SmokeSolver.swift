import Foundation

/// Smoke and fire on a small grid in their box (Stam's stable fluids): heat rises, smoke is carried by the air it
/// stirs, around the surfaces in the way and with the wind. Drawn as soft puffs in the scene's Look.
struct SmokeSolver {
    let recipe: FluidRecipe
    let emitter: Transform
    let box: Bounds
    let colliders: [FluidCollider]
    let fps: Int
    let nx: Int
    let ny: Int
    let nz: Int
    let cell: Double
    var density: [Float]
    var heat: [Float]
    var velocity: [SIMD3<Float>]
    var solid: [Bool]

    init(recipe: FluidRecipe, emitter: Transform, colliders: [FluidCollider], fps: Int) {
        self.recipe = recipe
        self.emitter = emitter
        box = FluidBox.make(recipe, at: emitter.position, ground: true)
        self.colliders = colliders
        self.fps = fps
        cell = box.size.maxComponent / 40
        nx = max(Int((box.size.x / cell).rounded()), 4)
        ny = max(Int((box.size.y / cell).rounded()), 4)
        nz = max(Int((box.size.z / cell).rounded()), 4)
        let count = nx * ny * nz
        density = Array(repeating: 0, count: count)
        heat = Array(repeating: 0, count: count)
        velocity = Array(repeating: .zero, count: count)
        solid = Array(repeating: false, count: count)
    }

    @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (z * ny + y) * nx + x }

    func centre(_ x: Int, _ y: Int, _ z: Int) -> Vec3 {
        box.min + Vec3(Double(x) + 0.5, Double(y) + 0.5, Double(z) + 0.5) * cell
    }

    mutating func step(_ dt: Double, time: Double, colliders places: [Transform], wind: Vec3) {
        markSolids(places)
        addSource(Float(dt), time: time)
        let fire = recipe.kind == .fire
        let lift: Float = fire ? 4.5 : 2.2
        let weight: Float = fire ? 0.2 : 0.4
        let air = wind.floats
        let step = Float(dt)
        for i in velocity.indices where !solid[i] {
            velocity[i].y += (lift * heat[i] - weight * density[i]) * step
            velocity[i] += (air - velocity[i]) * min(0.6 * step, 1) * (air == .zero ? 0 : 1)
        }
        velocity = advect(velocity, dt: dt)
        project()
        density = advect(density, dt: dt)
        heat = advect(heat, dt: dt)
        let fade = Float(exp(-(fire ? 2.4 : 0.25) * dt))
        let cool = Float(exp(-(fire ? 1.6 : 1.0) * dt))
        for i in density.indices {
            density[i] = solid[i] ? 0 : density[i] * fade
            heat[i] = solid[i] ? 0 : heat[i] * cool
        }
    }

    private mutating func markSolids(_ places: [Transform]) {
        guard !colliders.isEmpty else { return }
        for z in 0 ..< nz {
            for y in 0 ..< ny {
                for x in 0 ..< nx {
                    let point = centre(x, y, z)
                    solid[index(x, y, z)] = zip(colliders, places).contains { collider, place in
                        collider.field.distance(at: place.inverseApply(to: point)) < cell * 0.6
                    }
                }
            }
        }
    }

    /// Smoke and heat leave the source while it runs, rising.
    private mutating func addSource(_ dt: Float, time: Double) {
        guard time <= recipe.duration else { return }
        let radius = max(box.size.x, box.size.z) * 0.1
        let source = emitter.position
        let strength = Float(min(max(recipe.amount, 0.05), 1))
        for z in 0 ..< nz {
            for x in 0 ..< nx {
                for y in 0 ..< min(3, ny) {
                    let point = centre(x, y, z)
                    let distance = Vec3(point.x - source.x, 0, point.z - source.z).length
                    guard distance < radius else { continue }
                    let i = index(x, y, z)
                    let falloff = Float(1 - distance / radius)
                    density[i] = min(density[i] + 4 * strength * falloff * dt, 1.5)
                    heat[i] = min(heat[i] + (recipe.kind == .fire ? 9 : 3) * strength * falloff * dt, 1.5)
                    velocity[i].y += 2 * falloff * dt
                }
            }
        }
    }

    /// Each cell takes what was where the flow came from (trilinear), so big steps stay stable.
    private func advect<Value: SmokeValue>(_ field: [Value], dt: Double) -> [Value] {
        var result = field
        let back = Float(dt / cell)
        for z in 0 ..< nz {
            for y in 0 ..< ny {
                for x in 0 ..< nx {
                    let i = index(x, y, z)
                    guard !solid[i] else {
                        result[i] = .zero
                        continue
                    }
                    let from = SIMD3<Float>(Float(x), Float(y), Float(z)) - velocity[i] * back
                    result[i] = sample(field, at: from)
                }
            }
        }
        return result
    }

    private func sample<Value: SmokeValue>(_ field: [Value], at point: SIMD3<Float>) -> Value {
        let px = min(max(point.x, 0), Float(nx - 1))
        let py = min(max(point.y, 0), Float(ny - 1))
        let pz = min(max(point.z, 0), Float(nz - 1))
        let x0 = min(Int(px), nx - 2 < 0 ? 0 : nx - 2)
        let y0 = min(Int(py), ny - 2 < 0 ? 0 : ny - 2)
        let z0 = min(Int(pz), nz - 2 < 0 ? 0 : nz - 2)
        let fx = px - Float(x0)
        let fy = py - Float(y0)
        let fz = pz - Float(z0)
        func v(_ dx: Int, _ dy: Int, _ dz: Int) -> Value { field[index(x0 + dx, y0 + dy, z0 + dz)] }
        let c00 = v(0, 0, 0).mix(v(1, 0, 0), fx)
        let c10 = v(0, 1, 0).mix(v(1, 1, 0), fx)
        let c01 = v(0, 0, 1).mix(v(1, 0, 1), fx)
        let c11 = v(0, 1, 1).mix(v(1, 1, 1), fx)
        return c00.mix(c10, fy).mix(c01.mix(c11, fy), fz)
    }

    /// The flow made free of divergence: a pressure solved by Jacobi steps, its gradient taken away.
    private mutating func project() {
        var divergence = [Float](repeating: 0, count: velocity.count)
        var pressure = [Float](repeating: 0, count: velocity.count)
        func u(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> {
            guard x >= 0, y >= 0, z >= 0, x < nx, y < ny, z < nz else { return .zero }
            let i = index(x, y, z)
            return solid[i] ? .zero : velocity[i]
        }
        for z in 0 ..< nz {
            for y in 0 ..< ny {
                for x in 0 ..< nx {
                    divergence[index(x, y, z)] = 0.5 * (u(x + 1, y, z).x - u(x - 1, y, z).x + u(x, y + 1, z).y - u(x, y - 1, z).y
                        + u(x, y, z + 1).z - u(x, y, z - 1).z)
                }
            }
        }
        func p(_ x: Int, _ y: Int, _ z: Int, _ own: Float) -> Float {
            guard x >= 0, y >= 0, z >= 0, x < nx, y < ny, z < nz else { return own }
            let i = index(x, y, z)
            return solid[i] ? own : pressure[i]
        }
        for _ in 0 ..< 24 {
            var next = pressure
            for z in 0 ..< nz {
                for y in 0 ..< ny {
                    for x in 0 ..< nx {
                        let i = index(x, y, z)
                        guard !solid[i] else { continue }
                        let own = pressure[i]
                        let sum = p(x - 1, y, z, own) + p(x + 1, y, z, own) + p(x, y - 1, z, own) + p(x, y + 1, z, own) + p(x, y, z - 1, own)
                            + p(x, y, z + 1, own)
                        next[i] = (sum - divergence[i]) / 6
                    }
                }
            }
            pressure = next
        }
        for z in 0 ..< nz {
            for y in 0 ..< ny {
                for x in 0 ..< nx {
                    let i = index(x, y, z)
                    guard !solid[i] else { continue }
                    let own = pressure[i]
                    velocity[i] -= 0.5 * SIMD3<Float>(p(x + 1, y, z, own) - p(x - 1, y, z, own), p(x, y + 1, z, own) - p(x, y - 1, z, own),
                                                      p(x, y, z + 1, own) - p(x, y, z - 1, own))
                }
            }
        }
    }

    /// Soft puffs where there's smoke (fire glows by its heat), at most 1 600 of them.
    func look() -> PhysicsFrames.FluidLook {
        let fire = recipe.kind == .fire
        var cells: [Int] = []
        for i in density.indices where density[i] > 0.03 || (fire && heat[i] > 0.08) {
            cells.append(i)
        }
        let stride = max(cells.count / 1600, 1)
        var puffs: [Particle] = []
        var total = 0.0
        for (n, i) in cells.enumerated() where n % stride == 0 {
            let x = i % nx
            let y = (i / nx) % ny
            let z = i / (nx * ny)
            let amount = Double(density[i])
            total += amount
            let colour: RGBA = fire ? Self.flame(Double(heat[i]), base: recipe.color) : Self.alpha(recipe.color, min(amount * 0.8, 0.85))
            let jitter = Vec3(Double((i &* 7919) % 97) / 97 - 0.5, Double((i &* 104_729) % 89) / 89 - 0.5, Double((i &* 1_299_709) % 83) / 83 - 0.5)
            let size = cell * (1.4 + min(amount, 1)) * Double(stride).squareRoot()
            puffs.append(Particle(position: centre(x, y, z) + jitter * cell, velocity: Vec3(velocity[i]), size: size,
                                  color: colour, spin: Double(i % 17), life: 1 - min(amount, 1)))
        }
        return PhysicsFrames.FluidLook(puffs: puffs, amount: total)
    }

    static func alpha(_ colour: RGBA, _ a: Double) -> RGBA { RGBA(colour.r, colour.g, colour.b, a) }

    static func flame(_ heat: Double, base: RGBA) -> RGBA {
        let t = min(max(heat, 0), 1)
        let hot = RGBA(1, 0.95, 0.6)
        let warm = base
        let cool = RGBA(0.35, 0.3, 0.3)
        let colour = t > 0.5 ? warm.lerp(to: hot, (t - 0.5) * 2) : cool.lerp(to: warm, t * 2)
        return alpha(colour, min(0.25 + t, 0.95))
    }
}

/// What a smoke grid carries: numbers and velocities, mixed alike.
protocol SmokeValue {
    static var zero: Self { get }
    func mix(_ other: Self, _ t: Float) -> Self
}

extension Float: SmokeValue {
    func mix(_ other: Float, _ t: Float) -> Float { self + (other - self) * t }
}

extension SIMD3: SmokeValue where Scalar == Float {
    func mix(_ other: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { self + (other - self) * t }
}
