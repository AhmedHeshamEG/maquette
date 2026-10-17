import Foundation

/// The default set of character parts (law 12: a superb default library, our own shapes only). Each job has a few
/// styles; a style gives each piece of the part its mesh in the part's own space, with the pivot where it attaches:
/// a head and a body stand on their base, limbs hang from their top, tails reach back (−z) and wings out to the side,
/// face parts sit on the surface facing +z.
public enum PartSet {
    public struct Style: Hashable, Sendable, Identifiable {
        public let job: CharacterPart.Job
        public let name: String
        public let title: String
        public var id: String { "\(job.rawValue).\(name)" }
    }

    /// Every style of a job, the default first.
    public static func styles(for job: CharacterPart.Job) -> [Style] {
        names[job, default: []].map { Style(job: job, name: $0.0, title: $0.1) }
    }

    public static func defaultStyle(for job: CharacterPart.Job) -> String {
        names[job]?.first?.0 ?? "round"
    }

    static let names: [CharacterPart.Job: [(String, String)]] = [
        .head: [("round", "Round"), ("oval", "Oval"), ("square", "Square"), ("bean", "Bean")],
        .eye: [("round", "Round"), ("dot", "Dot"), ("sleepy", "Sleepy"), ("big", "Big")],
        .brow: [("line", "Line"), ("thick", "Thick"), ("arched", "Arched")],
        .mouth: [("oval", "Oval"), ("grin", "Grin"), ("beak", "Beak")],
        .nose: [("button", "Button"), ("long", "Long"), ("snout", "Snout")],
        .ear: [("round", "Round"), ("pointy", "Pointy"), ("floppy", "Floppy"), ("cat", "Cat")],
        .hair: [("short", "Short"), ("spiky", "Spiky"), ("tuft", "Tuft"), ("long", "Long"), ("mohawk", "Mohawk")],
        .body: [("bean", "Bean"), ("box", "Box"), ("pear", "Pear"), ("round", "Round"), ("long", "Long")],
        .arm: [("tube", "Tube"), ("noodle", "Noodle"), ("chunky", "Chunky")],
        .leg: [("tube", "Tube"), ("stubby", "Stubby"), ("paw", "Paw"), ("hoof", "Hoof")],
        .tail: [("thin", "Thin"), ("bushy", "Bushy"), ("fin", "Fin")],
        .wing: [("feather", "Feather"), ("bat", "Bat"), ("bug", "Bug")],
        .extra: [("horns", "Horns"), ("antenna", "Antennae"), ("hat", "Hat"), ("glasses", "Glasses"), ("bow", "Bow")]
    ]

    /// The colour a part of a job starts with.
    public static func colour(for job: CharacterPart.Job, style: String) -> RGBA {
        switch job {
        case .eye: style == "dot" ? RGBA.hex("#1E1A1C") : RGBA.hex("#F7F4EE")
        case .brow, .mouth: RGBA.hex("#2A1616")
        case .hair: RGBA.hex("#3B2A20")
        case .extra:
            switch style {
            case "glasses": RGBA.hex("#1E1A1C")
            case "hat": RGBA.hex("#2F3E5C")
            case "bow": RGBA.hex("#E4572E")
            default: RGBA.hex("#F1E3C8")
            }
        case .wing: style == "bug" ? RGBA.hex("#CFE8F2") : RGBA.hex("#F1E3C8")
        default: RGBA.hex("#F2A65A")
        }
    }

    /// The mesh of one piece of a part (`segment` for hinged parts; `side` mirrors what isn't symmetric).
    public static func mesh(_ job: CharacterPart.Job, style: String, segment: Int = 0, side: CharacterPart.Side = .middle) -> MeshData {
        switch job {
        case .head: head(style)
        case .eye: eye(style)
        case .brow: brow(style)
        case .mouth: mouth(style)
        case .nose: nose(style)
        case .ear: ear(style, side: side)
        case .hair: hair(style)
        case .body: body(style)
        case .arm: arm(style, segment: segment)
        case .leg: leg(style, segment: segment)
        case .tail: tail(style, segment: segment)
        case .wing: wing(style, segment: segment, side: side)
        case .extra: extra(style, side: side)
        }
    }

    /// Where the next piece of a hinged part hangs, in this piece's own space (a limb's elbow or knee, a tail's next bend,
    /// a wing's fold).
    public static func nextPivot(_ job: CharacterPart.Job, style: String, segment: Int, side: CharacterPart.Side = .middle) -> Vec3 {
        switch job {
        case .arm: Vec3(0, segment == 0 ? -0.26 : -0.24, 0)
        case .leg: Vec3(0, -legLengths(style)[min(segment, 1)], 0)
        case .tail: Vec3(0, 0, style == "bushy" ? -0.16 : -0.13)
        case .wing: Vec3((side == .right ? -1 : 1) * 0.32, 0, 0)
        default: .zero
        }
    }

    /// A leg's upper and lower lengths (its foot is `footHeight` tall).
    static func legLengths(_ style: String) -> [Double] {
        style == "stubby" ? [0.12, 0.1] : [0.22, 0.2]
    }

    /// How far a leg of this style reaches from its top to the ground.
    public static func legReach(_ style: String) -> Double {
        legLengths(style).reduce(0, +) + footHeight
    }

    public static let footHeight = 0.08

    /// The pupil that sits on an eye of this style (nil: the eye is all one colour).
    public static func pupil(for style: String) -> MeshData? {
        switch style {
        case "dot": nil
        case "big": PartShapes.centredEllipsoid(Vec3(0.09, 0.09, 0.04)).transformed(Transform(position: Vec3(0, 0, 0.085)))
        default: PartShapes.centredEllipsoid(Vec3(0.05, 0.055, 0.03)).transformed(Transform(position: Vec3(0, 0, 0.05)))
        }
    }

    // MARK: Heads and bodies

    static func head(_ style: String) -> MeshData {
        switch style {
        case "oval": PartShapes.ellipsoid(Vec3(0.44, 0.56, 0.46))
        case "square": PartShapes.block(Vec3(0.48, 0.48, 0.46), round: 0.25)
        case "bean": PartShapes.ellipsoid(Vec3(0.54, 0.44, 0.46))
        default: PartShapes.ellipsoid(Vec3(0.5, 0.5, 0.48))
        }
    }

    static func body(_ style: String) -> MeshData {
        switch style {
        case "box": PartShapes.block(Vec3(0.46, 0.56, 0.32))
        case "pear": PartShapes.lathe([(0, 0.56), (0.13, 0.54), (0.18, 0.42), (0.23, 0.2), (0.24, 0.08), (0.18, 0.0), (0, 0)])
            .transformed(Transform(scale: Vec3(1, 1, 0.75)))
        case "round": PartShapes.ellipsoid(Vec3(0.52, 0.52, 0.48))
        case "long":
            // A four-legged body: a capsule lying along z, standing on its lowest point.
            PartShapes.capsule(radius: 0.17, length: 0.42).transformed(Transform(position: Vec3(0, 0.17, -0.21), rotation: Quat(angle: -.pi / 2, axis: .unitX)))
        default: PartShapes.lathe([(0, 0.56), (0.12, 0.55), (0.19, 0.48), (0.22, 0.32), (0.22, 0.14), (0.17, 0.02), (0, 0)])
            .transformed(Transform(scale: Vec3(1.05, 1, 0.8)))
        }
    }

    // MARK: Face

    static func eye(_ style: String) -> MeshData {
        switch style {
        case "dot": PartShapes.centredEllipsoid(Vec3(0.05, 0.065, 0.04)).transformed(Transform(position: Vec3(0, 0, 0.012)))
        case "sleepy": PartShapes.centredEllipsoid(Vec3(0.11, 0.07, 0.06)).transformed(Transform(position: Vec3(0, 0, 0.02)))
        case "big": PartShapes.centredEllipsoid(Vec3(0.2, 0.2, 0.14)).transformed(Transform(position: Vec3(0, 0, 0.03)))
        default: PartShapes.centredEllipsoid(Vec3(0.11, 0.12, 0.08)).transformed(Transform(position: Vec3(0, 0, 0.02)))
        }
    }

    static func brow(_ style: String) -> MeshData {
        let size: Vec3 = style == "thick" ? Vec3(0.12, 0.04, 0.035) : Vec3(0.1, 0.022, 0.025)
        let mesh = PartShapes.centredEllipsoid(size, segments: 10, rings: 6).transformed(Transform(position: Vec3(0, 0, 0.012)))
        guard style == "arched", let bounds = mesh.bounds else { return mesh }
        return FaceBend(smile: -0.8).bend(mesh, bounds: bounds, side: 0)
    }

    static func mouth(_ style: String) -> MeshData {
        switch style {
        case "grin":
            let lens = PartShapes.centredEllipsoid(Vec3(0.2, 0.05, 0.03)).transformed(Transform(position: Vec3(0, 0, 0.01)))
            return lens.bounds.map { FaceBend(smile: 0.45).bend(lens, bounds: $0, side: 0) } ?? lens
        case "beak":
            return PartShapes.cone(radius: 0.06, height: 0.12, segments: 8).transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
                .transformed(Transform(scale: Vec3(1.2, 0.8, 1)))
        default:
            return PartShapes.centredEllipsoid(Vec3(0.15, 0.05, 0.03)).transformed(Transform(position: Vec3(0, 0, 0.01)))
        }
    }

    static func nose(_ style: String) -> MeshData {
        switch style {
        case "long": PartShapes.cone(radius: 0.035, height: 0.14, segments: 8).transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
        case "snout": PartShapes.capsule(radius: 0.06, length: 0.07, segments: 10)
            .transformed(Transform(position: Vec3(0, 0, 0.06), rotation: Quat(angle: -.pi / 2, axis: .unitX)))
            .transformed(Transform(scale: Vec3(1.15, 0.85, 1)))
        default: PartShapes.centredEllipsoid(Vec3(0.06, 0.05, 0.05)).transformed(Transform(position: Vec3(0, 0, 0.015)))
        }
    }

    static func ear(_ style: String, side: CharacterPart.Side) -> MeshData {
        switch style {
        case "pointy": return PartShapes.cone(radius: 0.05, height: 0.16, segments: 8).transformed(Transform(scale: Vec3(1, 1, 0.5)))
        case "floppy":
            // Hangs down the side of the head.
            return PartShapes.ellipsoid(Vec3(0.07, 0.2, 0.12)).transformed(Transform(position: Vec3(side.sign * 0.02, -0.17, 0)))
        case "cat": return PartShapes.cone(radius: 0.07, height: 0.12, segments: 4).transformed(Transform(scale: Vec3(1, 1, 0.45)))
        default: return PartShapes.ellipsoid(Vec3(0.11, 0.13, 0.05))
        }
    }

    /// Hair fits a head of the default size (0.5 m) standing at the head's own origin.
    static func hair(_ style: String) -> MeshData {
        let cap = PartShapes.lathe((0 ... 5).map { ring in
            let phi = Double(ring) / 10 * .pi
            return (0.27 * sin(phi), 0.25 + 0.27 * cos(phi))
        } + [(0, 0.25)])
        switch style {
        case "spiky":
            var pieces = [cap]
            for (x, z, lean) in [(0.0, 0.0, 0.0), (0.12, 0.04, -0.4), (-0.12, 0.04, 0.4), (0.06, -0.12, -0.25), (-0.06, -0.12, 0.25),
                                 (0.0, 0.13, 0.0)] {
                let spike = PartShapes.cone(radius: 0.06, height: 0.16, segments: 6)
                    .transformed(Transform(position: Vec3(x, 0.47, z), rotation: Quat(angle: lean, axis: .unitZ)))
                pieces.append(spike)
            }
            return PartShapes.joined(pieces)
        case "tuft":
            return PartShapes.joined([0.0, 0.09, -0.08].map { x in
                PartShapes.centredEllipsoid(Vec3(0.12, 0.1, 0.12)).transformed(Transform(position: Vec3(x, 0.53, 0.02)))
            })
        case "long":
            let back = PartShapes.block(Vec3(0.5, 0.42, 0.12), round: 0.4).transformed(Transform(position: Vec3(0, -0.02, -0.2)))
            return PartShapes.joined([cap, back])
        case "mohawk":
            return PartShapes.slab([(-0.03, 0.44), (0.02, 0.6), (0.06, 0.58), (0.1, 0.48)], thickness: 0.05)
                .transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitY))).transformed(Transform(position: Vec3(0, 0, 0.03)))
        default:
            return cap
        }
    }

    // MARK: Limbs

    static func arm(_ style: String, segment: Int) -> MeshData {
        let r: Double = style == "noodle" ? 0.035 : (style == "chunky" ? 0.085 : 0.06)
        switch segment {
        case 0: return PartShapes.capsule(radius: r, length: 0.26)
        case 1: return PartShapes.capsule(radius: r * 0.92, length: 0.24)
        default:
            let hand = style == "chunky" ? Vec3(0.17, 0.15, 0.13) : Vec3(0.13, 0.14, 0.1)
            return PartShapes.ellipsoid(hand).transformed(Transform(position: Vec3(0, -hand.y, 0)))
        }
    }

    static func leg(_ style: String, segment: Int) -> MeshData {
        let r: Double = style == "stubby" ? 0.1 : 0.075
        let lengths = legLengths(style)
        switch segment {
        case 0: return PartShapes.capsule(radius: r, length: lengths[0])
        case 1: return PartShapes.capsule(radius: r * 0.9, length: lengths[1])
        default:
            switch style {
            case "paw": return PartShapes.ellipsoid(Vec3(0.14, 0.08, 0.16)).transformed(Transform(position: Vec3(0, -0.08, 0.02)))
            case "hoof": return PartShapes.cone(radius: 0.07, height: 0.08, segments: 8).transformed(Transform(position: Vec3(0, -0.08, 0)))
            default:
                return PartShapes.block(Vec3(0.13, 0.08, 0.22), round: 0.35).transformed(Transform(position: Vec3(0, -0.08, 0.04)))
            }
        }
    }

    static func tail(_ style: String, segment: Int) -> MeshData {
        let t = Double(segment) / 4
        switch style {
        case "bushy":
            return PartShapes.centredEllipsoid(Vec3(0.13 - t * 0.03, 0.13 - t * 0.03, 0.2))
                .transformed(Transform(position: Vec3(0, 0, -0.08)))
        case "fin" where segment == 3:
            return PartShapes.slab([(-0.12, 0.0), (0.12, 0.0), (0.04, -0.16), (-0.04, -0.16)], thickness: 0.03)
                .transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
        default:
            let r = 0.05 * (1 - t * 0.55)
            return PartShapes.capsule(radius: r, length: 0.13, bottomRadius: r * 0.85)
                .transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
        }
    }

    static func wing(_ style: String, segment: Int, side: CharacterPart.Side) -> MeshData {
        let outline: [(Double, Double)] = switch (style, segment) {
        case ("bat", 0): [(0, 0.05), (0.32, 0.12), (0.34, -0.04), (0.18, -0.16), (0, -0.1)]
        case ("bat", _): [(0, 0.12), (0.34, 0.02), (0.22, -0.08), (0.12, -0.03), (0, -0.04)]
        case ("bug", 0): [(0, 0.06), (0.2, 0.14), (0.36, 0.1), (0.38, 0.0), (0.2, -0.06), (0, -0.05)]
        case ("bug", _): [(0, 0.1), (0.2, 0.06), (0.26, 0.0), (0.18, -0.04), (0, 0.0)]
        case (_, 0): [(0, 0.06), (0.34, 0.1), (0.36, -0.06), (0.16, -0.18), (0, -0.12)]
        default: [(0, 0.1), (0.36, 0.0), (0.3, -0.1), (0.1, -0.14), (0, -0.06)]
        }
        let thickness = style == "feather" ? 0.035 : 0.015
        // Laid flat (x out, z back), out to the part's side.
        let mirrored = outline.map { (side == .right ? -$0.0 : $0.0, $0.1) }
        return PartShapes.slab(mirrored, thickness: thickness).transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
    }

    static func extra(_ style: String, side: CharacterPart.Side) -> MeshData {
        switch style {
        case "antenna":
            let stalk = PartShapes.capsule(radius: 0.012, length: 0.16, segments: 6).transformed(Transform(position: Vec3(0, 0.16, 0)))
            let ball = PartShapes.centredEllipsoid(Vec3(0.06, 0.06, 0.06)).transformed(Transform(position: Vec3(0, 0.19, 0)))
            return PartShapes.joined([stalk, ball])
        case "hat":
            let brim = PartShapes.lathe([(0, 0.02), (0.3, 0.02), (0.3, 0.0), (0, 0)], segments: 14)
            let crown = PartShapes.lathe([(0, 0.24), (0.17, 0.24), (0.19, 0.02), (0, 0.02)], segments: 14)
            return PartShapes.joined([brim, crown])
        case "glasses":
            let ring = PrimitiveMesh.torus(segments: 14, sides: 6, major: 0.05, minor: 0.008)
            let left = ring.transformed(Transform(position: Vec3(0.065, 0, 0.02), rotation: Quat(angle: .pi / 2, axis: .unitX)))
            let right = ring.transformed(Transform(position: Vec3(-0.065, 0, 0.02), rotation: Quat(angle: .pi / 2, axis: .unitX)))
            let bridge = PartShapes.capsule(radius: 0.007, length: 0.03, segments: 6)
                .transformed(Transform(position: Vec3(-0.015, 0.02, 0.02), rotation: Quat(angle: .pi / 2, axis: .unitZ)))
            return PartShapes.joined([left, right, bridge])
        case "bow":
            let knot = PartShapes.centredEllipsoid(Vec3(0.04, 0.04, 0.04))
            let loop = PartShapes.cone(radius: 0.05, height: 0.08, segments: 6)
            let left = loop.transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitZ)))
            let right = loop.transformed(Transform(rotation: Quat(angle: -.pi / 2, axis: .unitZ)))
            return PartShapes.joined([knot, left, right])
        default:
            // A horn curving out to its side.
            let lean = side == .right ? 0.35 : -0.35
            return PartShapes.cone(radius: 0.045, height: 0.15, segments: 8).transformed(Transform(rotation: Quat(angle: lean, axis: .unitZ)))
        }
    }
}
