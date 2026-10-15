import Foundation

/// The procedural patterns behind materials, evaluated at a point in pattern space (object space divided by the
/// material's scale, so 1 is one repeat). Solid patterns (noise, wood, marble, stone…) are 3D, so they wrap round any
/// shape with no seam; laid patterns (bricks, tiles, planks, weave) are 2D and blended over the three planes by how the
/// surface faces them. Everything is seeded arithmetic, so the same point always gives the same answer on every device.
public enum MaterialPatterns {
    /// What a pattern does at one point: how much of the second colour, a nudge to roughness, how much it dulls metal,
    /// and its height (0.5 is the surface).
    public struct Shape: Hashable, Sendable {
        public var mix: Float
        public var roughness: Float
        public var dull: Float
        public var height: Float

        public init(mix: Float = 0, roughness: Float = 0, dull: Float = 0, height: Float = 0.5) {
            self.mix = mix
            self.roughness = roughness
            self.dull = dull
            self.height = height
        }
    }

    public static func evaluate(_ pattern: MaterialPattern, at p: SIMD3<Float>, normal: SIMD3<Float>) -> Shape {
        switch pattern {
        case .none: Shape()
        case .noise: mottled(p)
        case .wood: wood(p)
        case .brushed: brushed(p)
        case .marble: marble(p)
        case .stone: stone(p)
        case .concrete: concrete(p)
        case .leather: leather(p)
        case .rust: rust(p)
        case .sand: sand(p)
        case .planks, .bricks, .tiles, .weave: laid(pattern, p, normal)
        }
    }

    // MARK: Solid patterns

    static func mottled(_ p: SIMD3<Float>) -> Shape {
        let n = PatternNoise.fbm(p * 2, octaves: 4)
        return Shape(mix: smooth(0.3, 0.7, n), roughness: (n - 0.5) * 0.2, height: n)
    }

    /// Rings round the upright axis, wobbled by noise, with fine grain along them.
    static func wood(_ p: SIMD3<Float>) -> Shape {
        let warp = PatternNoise.fbm(p * SIMD3<Float>(0.6, 0.15, 0.6), octaves: 3) * 1.6
        let rings = (p.x * p.x + p.z * p.z).squareRoot() * 6 + warp
        let ring = rings - rings.rounded(.down)
        let late = smooth(0.55, 0.95, ring)
        let grain = PatternNoise.value(SIMD3<Float>(p.x * 40, p.y * 1.5, p.z * 40))
        let mix = min(late * 0.85 + grain * 0.25, 1)
        return Shape(mix: mix, roughness: late * 0.1, height: 0.5 + (0.5 - late) * 0.6 - grain * 0.1)
    }

    /// Fine streaks along the x axis.
    static func brushed(_ p: SIMD3<Float>) -> Shape {
        let streak = PatternNoise.fbm(SIMD3<Float>(p.x * 0.5, p.y * 60, p.z * 60), octaves: 3)
        return Shape(mix: streak * 0.6, roughness: (streak - 0.5) * 0.25, dull: 0, height: 0.4 + streak * 0.2)
    }

    static func marble(_ p: SIMD3<Float>) -> Shape {
        let turbulence = PatternNoise.fbm(p * 1.5, octaves: 5) * 5
        let vein = abs(sin((p.x + p.y * 0.4) * 3 + turbulence))
        let line = 1 - smooth(0.0, 0.18, vein)
        return Shape(mix: line, roughness: line * 0.1, height: 0.5 - line * 0.1)
    }

    /// Cells with dark cracks between them.
    static func stone(_ p: SIMD3<Float>) -> Shape {
        let cells = PatternNoise.cells(p * 2.5)
        let crack = 1 - smooth(0.0, 0.08, cells.edge)
        let face = PatternNoise.fbm(p * 6, octaves: 3)
        return Shape(mix: max(crack, cells.value * 0.5), roughness: crack * 0.15 + (face - 0.5) * 0.2, dull: crack,
                     height: 0.6 - crack * 0.5 + (face - 0.5) * 0.2)
    }

    /// Fine grain with small pores.
    static func concrete(_ p: SIMD3<Float>) -> Shape {
        let grain = PatternNoise.fbm(p * 8, octaves: 4)
        let pore = 1 - smooth(0.0, 0.05, PatternNoise.cells(p * 14).distance)
        return Shape(mix: smooth(0.35, 0.75, grain) * 0.7 + pore * 0.5, roughness: 0.05 + pore * 0.1, height: 0.5 + (grain - 0.5) * 0.4 - pore * 0.4)
    }

    /// Small puffy cells with creases.
    static func leather(_ p: SIMD3<Float>) -> Shape {
        let cells = PatternNoise.cells(p * 18)
        let crease = 1 - smooth(0.0, 0.12, cells.edge)
        return Shape(mix: crease * 0.8, roughness: -crease * 0.1, height: 0.65 - crease * 0.45)
    }

    /// Patches of rust eating a dark metal: the second colour is the rust, which isn't metal.
    static func rust(_ p: SIMD3<Float>) -> Shape {
        let patch = smooth(0.42, 0.6, PatternNoise.fbm(p * 1.5, octaves: 5))
        let flake = PatternNoise.fbm(p * 12, octaves: 2)
        return Shape(mix: min(patch + flake * 0.2 * patch, 1), roughness: patch * 0.3, dull: patch, height: 0.45 + patch * 0.2 + flake * 0.1 * patch)
    }

    static func sand(_ p: SIMD3<Float>) -> Shape {
        let grain = PatternNoise.value(p * 60)
        let ripple = sin(p.x * 4 + PatternNoise.fbm(p, octaves: 2) * 3) * 0.5 + 0.5
        return Shape(mix: grain * 0.6, roughness: (grain - 0.5) * 0.1, height: 0.4 + ripple * 0.2 + grain * 0.1)
    }

    // MARK: Laid patterns

    /// A 2D pattern on each of the three planes, blended by how the surface faces them.
    static func laid(_ pattern: MaterialPattern, _ p: SIMD3<Float>, _ n: SIMD3<Float>) -> Shape {
        var weights = pointwiseMax(n, -n)
        weights = weights * weights * weights * weights
        weights /= max(weights.x + weights.y + weights.z, 1e-6)
        var result = Shape(mix: 0, roughness: 0, dull: 0, height: 0)
        for (weight, uv, seed) in [(weights.x, SIMD2<Float>(p.z, p.y), Float(0)), (weights.y, SIMD2<Float>(p.x, p.z), 1),
                                   (weights.z, SIMD2<Float>(p.x, p.y), 2)] where weight > 0.001 {
            let shape = flat(pattern, uv, seed: seed)
            result.mix += shape.mix * weight
            result.roughness += shape.roughness * weight
            result.dull += shape.dull * weight
            result.height += shape.height * weight
        }
        return result
    }

    static func flat(_ pattern: MaterialPattern, _ uv: SIMD2<Float>, seed: Float) -> Shape {
        switch pattern {
        case .bricks: bricks(uv, seed: seed)
        case .tiles: tiles(uv, seed: seed)
        case .planks: planks(uv, seed: seed)
        case .weave: weave(uv)
        default: Shape()
        }
    }

    /// Running bond: a brick is one long and half high, every other row shifted by half; the mortar is the second
    /// colour.
    static func bricks(_ uv: SIMD2<Float>, seed: Float) -> Shape {
        let row = (uv.y * 2).rounded(.down)
        let x = uv.x + (row.truncatingRemainder(dividingBy: 2) == 0 ? 0 : 0.5)
        let cell = SIMD2<Float>(x - x.rounded(.down), uv.y * 2 - row)
        let mortar = 1 - min(smooth(0.0, 0.035, cell.x), smooth(0.0, 0.035, 1 - cell.x), smooth(0.0, 0.07, cell.y), smooth(0.0, 0.07, 1 - cell.y))
        let tone = PatternNoise.hash(SIMD3<Float>(x.rounded(.down), row, seed)) * 0.35
        return Shape(mix: max(mortar, tone), roughness: mortar * 0.1, dull: mortar, height: 0.7 - mortar * 0.6)
    }

    static func tiles(_ uv: SIMD2<Float>, seed: Float) -> Shape {
        let cell = uv - uv.rounded(.down)
        let grout = 1 - min(smooth(0.0, 0.03, cell.x), smooth(0.0, 0.03, 1 - cell.x), smooth(0.0, 0.03, cell.y), smooth(0.0, 0.03, 1 - cell.y))
        let tone = PatternNoise.hash(SIMD3<Float>(uv.x.rounded(.down), uv.y.rounded(.down), seed)) * 0.15
        return Shape(mix: max(grout, tone), roughness: grout * 0.4 - (1 - grout) * 0.1, dull: grout, height: 0.65 - grout * 0.55)
    }

    /// Boards one wide and four long, ends staggered, each with its own grain and a gap between them.
    static func planks(_ uv: SIMD2<Float>, seed: Float) -> Shape {
        let column = uv.x.rounded(.down)
        let offset = PatternNoise.hash(SIMD3<Float>(column, 7, seed)) * 4
        let along = (uv.y + offset) / 4
        let board = along.rounded(.down)
        let cell = SIMD2<Float>(uv.x - column, along - board)
        let gap = 1 - min(smooth(0.0, 0.02, cell.x), smooth(0.0, 0.02, 1 - cell.x), smooth(0.0, 0.006, cell.y), smooth(0.0, 0.006, 1 - cell.y))
        let tone = PatternNoise.hash(SIMD3<Float>(column, board, seed))
        let grain = wood(SIMD3<Float>(cell.x * 0.3 + tone * 5, cell.y * 8, tone * 3))
        return Shape(mix: max(gap, grain.mix * 0.8 + tone * 0.2), roughness: grain.roughness, height: gap > 0.5 ? 0.1 : grain.height)
    }

    /// Threads over and under each other, twelve to a repeat.
    static func weave(_ uv: SIMD2<Float>) -> Shape {
        let t = uv * 12
        let cell = SIMD2<Float>(t.x.rounded(.down), t.y.rounded(.down))
        let warpOver = (cell.x + cell.y).truncatingRemainder(dividingBy: 2) == 0
        let f = t - cell
        let across = warpOver ? sin(f.x * .pi) : sin(f.y * .pi)
        let thread = sin((warpOver ? f.y : f.x) * .pi * 6) * 0.5 + 0.5
        return Shape(mix: warpOver ? 0.25 : 0.75 - thread * 0.1, roughness: 0.05, height: across * 0.7 + 0.15)
    }

    // MARK: Helpers

    @inline(__always) static func smooth(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Seeded value noise in 3D: a hash per lattice corner, smoothly interpolated; layered as fractal noise; and a cell
/// pattern (each cell's nearest seed point). Pure arithmetic, identical everywhere.
public enum PatternNoise {
    /// A number 0…1 for a lattice point.
    @inline(__always) public static func hash(_ p: SIMD3<Float>) -> Float {
        var h = lattice(p.x) &* 0x8DA6_B343
        h ^= lattice(p.y) &* 0xD816_3841
        h ^= lattice(p.z) &* 0xCB1A_B31F
        h ^= h >> 13
        h = h &* 0x5BD1_E995
        h ^= h >> 15
        return Float(h & 0x00FF_FFFF) / Float(0x00FF_FFFF)
    }

    /// A lattice coordinate as bits (anything not finite, or beyond a billion, folds to the edge: never a trap).
    @inline(__always) static func lattice(_ value: Float) -> UInt32 {
        guard value.isFinite else { return 0 }
        return UInt32(bitPattern: Int32(min(max(value, -1e9), 1e9)))
    }

    /// Smooth value noise, 0…1.
    public static func value(_ p: SIMD3<Float>) -> Float {
        let i = SIMD3<Float>(p.x.rounded(.down), p.y.rounded(.down), p.z.rounded(.down))
        let f = p - i
        let u = f * f * (SIMD3<Float>(repeating: 3) - 2 * f)
        func corner(_ x: Float, _ y: Float, _ z: Float) -> Float { hash(i + SIMD3<Float>(x, y, z)) }
        let x00 = corner(0, 0, 0) + (corner(1, 0, 0) - corner(0, 0, 0)) * u.x
        let x10 = corner(0, 1, 0) + (corner(1, 1, 0) - corner(0, 1, 0)) * u.x
        let x01 = corner(0, 0, 1) + (corner(1, 0, 1) - corner(0, 0, 1)) * u.x
        let x11 = corner(0, 1, 1) + (corner(1, 1, 1) - corner(0, 1, 1)) * u.x
        let y0 = x00 + (x10 - x00) * u.y
        let y1 = x01 + (x11 - x01) * u.y
        return y0 + (y1 - y0) * u.z
    }

    /// Fractal noise: octaves of value noise, each twice as fine and half as strong, 0…1.
    public static func fbm(_ p: SIMD3<Float>, octaves: Int) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, total: Float = 0
        var point = p
        for octave in 0 ..< max(octaves, 1) {
            sum += value(point + Float(octave) * 17.31) * amplitude
            total += amplitude
            amplitude *= 0.5
            point *= 2.03
        }
        return sum / total
    }

    /// The nearest and second nearest seed among the cells around a point: the distance to the nearest, how far the
    /// point is from the edge between them, and a number 0…1 for the nearest cell.
    public static func cells(_ p: SIMD3<Float>) -> (distance: Float, edge: Float, value: Float) {
        let base = SIMD3<Float>(p.x.rounded(.down), p.y.rounded(.down), p.z.rounded(.down))
        var nearest: Float = .greatestFiniteMagnitude, second: Float = .greatestFiniteMagnitude
        var id: Float = 0
        for dz in -1 ... 1 {
            for dy in -1 ... 1 {
                for dx in -1 ... 1 {
                    let cell = base + SIMD3<Float>(Float(dx), Float(dy), Float(dz))
                    let seed = cell + SIMD3<Float>(hash(cell), hash(cell + 31.7), hash(cell + 67.1))
                    let d = p - seed
                    let distance = (d * d).sum().squareRoot()
                    if distance < nearest {
                        second = nearest
                        nearest = distance
                        id = hash(cell + 11.3)
                    } else if distance < second {
                        second = distance
                    }
                }
            }
        }
        return (nearest, (second - nearest) * 0.5, id)
    }
}
