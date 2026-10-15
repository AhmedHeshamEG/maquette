import Foundation

/// Water as position-based fluid (Macklin & Müller, 2013): drops that keep their density, poured from a tap or let go as
/// a block, falling, sliding and pooling against every surface in their box. Small-scale on purpose (a glass, a sink, a
/// puddle); the stage plays it from the cache.
struct LiquidSolver {
    let recipe: FluidRecipe
    let emitter: Transform
    let box: Bounds
    let colliders: [FluidCollider]
    let ground: Bool
    let gravity: Double
    let fps: Int
    let spacing: Float
    let h: Float
    let restDensity: Float
    let relaxation: Float
    let tensileScale: Float
    var positions: [SIMD3<Float>] = []
    var velocities: [SIMD3<Float>] = []
    var owed: Double = 0
    var seed: UInt64

    static let maxParticles = 5000

    init(recipe: FluidRecipe, emitter: Transform, colliders: [FluidCollider], ground: Bool, gravity: Double, fps: Int) {
        self.recipe = recipe
        self.emitter = emitter
        box = FluidBox.make(recipe, at: emitter.position, ground: ground)
        self.colliders = colliders
        self.ground = ground
        self.gravity = gravity
        self.fps = fps
        let litres = recipe.kind == .pour ? recipe.amount * recipe.duration : recipe.amount
        let cubic = max(litres / 1000, 1e-6)
        spacing = Float(max(pow(cubic / Double(Self.maxParticles), 1.0 / 3.0), 0.004))
        h = spacing * 2
        var lattice: [SIMD3<Float>] = []
        for x in -3 ... 3 {
            for y in -3 ... 3 {
                for z in -3 ... 3 {
                    lattice.append(SIMD3<Float>(Float(x), Float(y), Float(z)) * spacing)
                }
            }
        }
        let poly = Kernel(h: spacing * 2)
        let rest = lattice.reduce(0) { $0 + poly.w($1) }
        restDensity = rest
        let gradients = lattice.reduce(Float(0)) { total, offset in
            let g = poly.gradient(offset) / rest
            return total + dot3(g, g)
        }
        relaxation = gradients * 0.05
        tensileScale = 1 / max(gradients, 1e-12)
        var hasher = StableHasher()
        hasher.add(Double(emitter.position.x))
        hasher.add(Double(emitter.position.z))
        seed = hasher.value
        if recipe.kind == .splash { fillBlock(cubic) }
    }

    /// A block of water the size of its volume, centred on the emitter.
    private mutating func fillBlock(_ volume: Double) {
        let side = Float(pow(volume, 1.0 / 3.0))
        let count = max(Int(side / spacing), 1)
        let centre = emitter.position.floats
        for x in 0 ..< count {
            for y in 0 ..< count {
                for z in 0 ..< count {
                    let offset = (SIMD3<Float>(Float(x), Float(y), Float(z)) + 0.5) * spacing - SIMD3<Float>(repeating: side / 2)
                    positions.append(centre + offset)
                    velocities.append(.zero)
                }
            }
        }
    }

    /// Drops leave the tap on a disc facing down the emitter's -Y.
    private mutating func pour(_ dt: Double, time: Double) {
        guard recipe.kind == .pour, time <= recipe.duration, positions.count < Self.maxParticles else { return }
        let rate = recipe.amount / 1000
        let radius = max(recipe.width / 2, Double(spacing))
        let area = Double.pi * radius * radius
        let speed = Float(max(rate / area, 0.3))
        owed += rate * dt / Double(spacing * spacing * spacing)
        let down = emitter.applyDirection(Vec3(0, -1, 0)).normalized
        let side = Self.perpendicular(down)
        let other = down.cross(side)
        var random = SeededRandom(seed: seed)
        while owed >= 1, positions.count < Self.maxParticles {
            owed -= 1
            let angle = random.range(0, 2 * .pi)
            let r = radius * random.unit().squareRoot()
            let point = emitter.position + side * (cos(angle) * r) + other * (sin(angle) * r) + down * random.range(0, Double(spacing))
            positions.append(point.floats)
            velocities.append(down.floats * speed)
        }
        seed = random.next()
    }

    static func perpendicular(_ axis: Vec3) -> Vec3 {
        (abs(axis.y) < 0.9 ? Vec3.unitY : Vec3.unitX).cross(axis).normalized
    }

    /// One frame: as many small steps as keep a drop from crossing a wall in one.
    mutating func step(_ dt: Double, time: Double, colliders places: [Transform], forces: [(ForceRecipe, Transform)]) {
        // Small enough that no drop moves more than half its spacing in one, so thin walls hold.
        let fastest = velocities.reduce(Float(1)) { max($0, length3($1)) }
        let substeps = min(max(Int((Double(fastest) * dt / Double(spacing * 0.5)).rounded(.up)), 2), 24)
        let small = dt / Double(substeps)
        for index in 0 ..< substeps {
            pour(small, time: time - dt + small * Double(index + 1))
            substep(Float(small), places: places, forces: forces)
        }
    }

    private mutating func substep(_ dt: Float, places: [Transform], forces: [(ForceRecipe, Transform)]) {
        guard !positions.isEmpty else { return }
        var predicted = predict(dt, places: places, forces: forces)
        var touched = [Bool](repeating: false, count: predicted.count)
        let grid = SpatialHash(predicted, cell: h)
        let kernel = Kernel(h: h)
        for _ in 0 ..< 3 {
            let lambdas = constraints(predicted, grid: grid, kernel: kernel)
            predicted = corrected(predicted, lambdas: lambdas, grid: grid, kernel: kernel, places: places, touched: &touched)
        }
        finish(predicted, touched: touched, grid: grid, kernel: kernel, dt: dt)
    }

    /// Gravity and forces move each drop, then it's kept out of every surface.
    private mutating func predict(_ dt: Float, places: [Transform], forces: [(ForceRecipe, Transform)]) -> [SIMD3<Float>] {
        let g = SIMD3<Float>(0, Float(-gravity), 0)
        var predicted = positions
        for i in positions.indices {
            var push = g
            let point = Vec3(positions[i])
            let velocity = Vec3(velocities[i])
            for (recipe, place) in forces {
                push += recipe.acceleration(at: point, velocity: velocity, place: place).floats
            }
            velocities[i] += push * dt
            predicted[i] = positions[i] + velocities[i] * dt
            _ = collide(&predicted[i], places: places)
        }
        return predicted
    }

    /// How much each drop is squeezed past the water's rest density, as PBF's λ.
    private func constraints(_ predicted: [SIMD3<Float>], grid: SpatialHash, kernel: Kernel) -> [Float] {
        var lambdas = [Float](repeating: 0, count: predicted.count)
        for i in predicted.indices {
            var density: Float = 0
            var gradientSum: Float = 0
            var own = SIMD3<Float>.zero
            grid.forEachNeighbour(of: predicted[i], in: predicted) { j in
                let d = predicted[i] - predicted[j]
                density += kernel.w(d)
                guard j != i else { return }
                let gradient = kernel.gradient(d) / restDensity
                gradientSum += dot3(gradient, gradient)
                own += gradient
            }
            let constraint = max(density / restDensity - 1, 0)
            lambdas[i] = -constraint / (gradientSum + dot3(own, own) + relaxation)
        }
        return lambdas
    }

    /// Each drop moved to undo the squeeze (with a little pull apart, so drops don't clump), out of every surface.
    private func corrected(_ predicted: [SIMD3<Float>], lambdas: [Float], grid: SpatialHash, kernel: Kernel, places: [Transform],
                           touched: inout [Bool]) -> [SIMD3<Float>] {
        let tensileReference = kernel.w(SIMD3<Float>(0.2 * h, 0, 0))
        var result = predicted
        for i in predicted.indices {
            var delta = SIMD3<Float>.zero
            grid.forEachNeighbour(of: predicted[i], in: predicted) { j in
                guard j != i else { return }
                let d = predicted[i] - predicted[j]
                let ratio = kernel.w(d) / tensileReference
                let tensile = -0.02 * ratio * ratio * ratio * ratio * tensileScale
                delta += kernel.gradient(d) * (lambdas[i] + lambdas[j] + tensile)
            }
            result[i] = predicted[i] + delta / restDensity
            if collide(&result[i], places: places) { touched[i] = true }
        }
        return result
    }

    /// Velocities from the move, a touch of viscosity, and drops that leave the box are gone.
    private mutating func finish(_ predicted: [SIMD3<Float>], touched: [Bool], grid: SpatialHash, kernel: Kernel, dt: Float) {
        var kept: [Int] = []
        kept.reserveCapacity(predicted.count)
        for i in predicted.indices {
            velocities[i] = (predicted[i] - positions[i]) / dt
            // Water drags on what it touches: a drop that met a surface keeps a little less of its speed.
            if touched[i] { velocities[i] *= 0.85 }
            var smoothing = SIMD3<Float>.zero
            grid.forEachNeighbour(of: predicted[i], in: predicted) { j in
                smoothing += (velocities[j] - velocities[i]) * kernel.w(predicted[i] - predicted[j])
            }
            velocities[i] += smoothing * (0.02 / restDensity)
            positions[i] = predicted[i]
            if inside(positions[i]) { kept.append(i) }
        }
        if kept.count < positions.count {
            positions = kept.map { positions[$0] }
            velocities = kept.map { velocities[$0] }
        }
    }

    private func inside(_ point: SIMD3<Float>) -> Bool {
        Double(point.x) >= box.min.x && Double(point.x) <= box.max.x && Double(point.z) >= box.min.z && Double(point.z) <= box.max.z
            && Double(point.y) <= box.max.y + 0.5
    }

    /// Out of every surface, onto the ground or the box's floor; true when it touched one.
    private func collide(_ point: inout SIMD3<Float>, places: [Transform]) -> Bool {
        let radius = Double(spacing) * 0.5
        let floor = Float(box.min.y + radius)
        var touched = false
        if point.y < floor {
            point.y = floor
            touched = true
        }
        for (collider, place) in zip(colliders, places) {
            let local = place.inverseApply(to: Vec3(point))
            let distance = collider.field.distance(at: local)
            // A coarse field rounds a thin wall's distance up; half a cell more keeps it solid.
            let reach = max(radius, collider.field.cell * 0.6)
            guard distance < reach else { continue }
            let away = place.applyDirection(collider.field.gradient(at: local))
            point += (away * (reach - distance)).floats
            touched = true
        }
        return touched
    }

    /// The water's surface and how much there is.
    func look() -> PhysicsFrames.FluidLook {
        let litres = Double(positions.count) * Double(spacing * spacing * spacing) * 1000
        return PhysicsFrames.FluidLook(surface: positions.isEmpty ? nil : FluidSurface.mesh(positions, spacing: Double(spacing)), amount: litres)
    }
}

/// Poly6 for density and Spiky's gradient for pressure (Müller et al., 2003).
struct Kernel {
    let h: Float
    let poly: Float
    let spiky: Float

    init(h: Float) {
        self.h = h
        poly = 315 / (64 * .pi * pow(h, 9))
        spiky = -45 / (.pi * pow(h, 6))
    }

    @inline(__always) func w(_ d: SIMD3<Float>) -> Float {
        let r2 = dot3(d, d)
        let h2 = h * h
        guard r2 < h2 else { return 0 }
        let q = h2 - r2
        return poly * q * q * q
    }

    @inline(__always) func gradient(_ d: SIMD3<Float>) -> SIMD3<Float> {
        let r = length3(d)
        guard r < h, r > 1e-9 else { return .zero }
        let q = h - r
        return d * (spiky * q * q / r)
    }
}

/// Particles sorted into hashed cells, so each finds its neighbours in the 27 cells around it.
struct SpatialHash {
    let cell: Float
    let size: Int
    var starts: [Int32]
    var order: [Int32]

    init(_ points: [SIMD3<Float>], cell: Float) {
        self.cell = cell
        let tableSize = max(points.count * 2, 64)
        size = tableSize
        var counts = [Int32](repeating: 0, count: tableSize + 1)
        let keys = points.map { Self.hash(Self.coordinate($0, cell: cell), size: tableSize) }
        for key in keys {
            counts[key + 1] += 1
        }
        for index in 1 ... tableSize {
            counts[index] += counts[index - 1]
        }
        starts = counts
        var cursor = counts
        order = [Int32](repeating: 0, count: points.count)
        for (index, key) in keys.enumerated() {
            order[Int(cursor[key])] = Int32(index)
            cursor[key] += 1
        }
    }

    static func coordinate(_ point: SIMD3<Float>, cell: Float) -> SIMD3<Int32> {
        SIMD3<Int32>(Int32((point.x / cell).rounded(.down)), Int32((point.y / cell).rounded(.down)), Int32((point.z / cell).rounded(.down)))
    }

    static func hash(_ c: SIMD3<Int32>, size: Int) -> Int {
        let value = (Int(c.x) &* 73_856_093) ^ (Int(c.y) &* 19_349_663) ^ (Int(c.z) &* 83_492_791)
        return abs(value % size)
    }

    /// Calls `body` with every particle within one cell of `point` (and some from colliding cells; kernels ignore them).
    @inline(__always) func forEachNeighbour(of point: SIMD3<Float>, in _: [SIMD3<Float>], _ body: (Int) -> Void) {
        let centre = Self.coordinate(point, cell: cell)
        withUnsafeTemporaryAllocation(of: Int.self, capacity: 27) { seen in
            var count = 0
            for dz in -1 ... 1 {
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 {
                        let key = Self.hash(centre &+ SIMD3<Int32>(Int32(dx), Int32(dy), Int32(dz)), size: size)
                        // Two neighbouring cells can hash alike; visit each bucket once.
                        if (0 ..< count).contains(where: { seen[$0] == key }) { continue }
                        seen[count] = key
                        count += 1
                        for slot in Int(starts[key]) ..< Int(starts[key + 1]) {
                            body(Int(order[slot]))
                        }
                    }
                }
            }
        }
    }
}
