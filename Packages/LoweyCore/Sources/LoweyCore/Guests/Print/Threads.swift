import Foundation

/// ISO metric screws (G1, Print, Giulia's M3 holes): the sizes from M2 to M10 with what a printed part needs for each.
/// Millimetres in the table; everything it makes is in metres.
public enum MetricScrew: String, CaseIterable, Sendable, Codable, Identifiable {
    case m2 = "M2", m2point5 = "M2.5", m3 = "M3", m4 = "M4", m5 = "M5", m6 = "M6", m8 = "M8", m10 = "M10"

    public var id: String { rawValue }

    /// One size's numbers, in millimetres.
    struct Sizes {
        /// Nominal (major) diameter and pitch.
        var d: Double
        var pitch: Double
        /// A medium clearance hole, the tap drill, a heat-set insert's hole and its depth.
        var clearance: Double
        var tap: Double
        var insert: Double
        var insertDepth: Double
        /// A socket head's diameter and height, a hex's width across flats, a nut's height.
        var head: Double
        var headHeight: Double
        var hex: Double
        var nut: Double

        init(_ values: [Double]) {
            d = values[0]
            pitch = values[1]
            clearance = values[2]
            tap = values[3]
            insert = values[4]
            insertDepth = values[5]
            head = values[6]
            headHeight = values[7]
            hex = values[8]
            nut = values[9]
        }
    }

    /// ISO 273 (clearance), 261 (pitch), 4762 (socket heads), 4032 (nuts); common heat-set inserts.
    var table: Sizes {
        switch self {
        case .m2: Sizes([2, 0.4, 2.4, 1.6, 3.2, 3, 3.8, 2, 4, 1.6])
        case .m2point5: Sizes([2.5, 0.45, 2.9, 2.05, 3.6, 4, 4.5, 2.5, 5, 2])
        case .m3: Sizes([3, 0.5, 3.4, 2.5, 4, 5.7, 5.5, 3, 5.5, 2.4])
        case .m4: Sizes([4, 0.7, 4.5, 3.3, 5.6, 8.1, 7, 4, 7, 3.2])
        case .m5: Sizes([5, 0.8, 5.5, 4.2, 6.4, 9.5, 8.5, 5, 8, 4.7])
        case .m6: Sizes([6, 1.0, 6.6, 5, 8, 12.7, 10, 6, 10, 5.2])
        case .m8: Sizes([8, 1.25, 9, 6.8, 10, 12.7, 13, 8, 13, 6.8])
        case .m10: Sizes([10, 1.5, 11, 8.5, 12, 14, 16, 10, 16, 8.4])
        }
    }

    public var diameter: Double { table.d / 1000 }
    public var pitch: Double { table.pitch / 1000 }
}

/// Holes for screws and printed threads (G1, Print).
public enum ScrewHole: String, CaseIterable, Sendable, Codable {
    /// The screw passes through freely.
    case clearance
    /// Through, with a pocket for a socket head so it sits flush.
    case counterbore
    /// The size a tap (or a self-tapping screw) cuts its thread in.
    case tapped
    /// The thread printed in the part (M5 and up print well; smaller ones are better tapped).
    case threaded
    /// A pocket for a heat-set brass insert.
    case insert

    public var title: String {
        switch self {
        case .clearance: "Clearance"
        case .counterbore: "Counterbored"
        case .tapped: "For a tap"
        case .threaded: "Threaded"
        case .insert: "Heat-set insert"
        }
    }

    /// The solid a hole cuts: from `point` on the surface `depth` into the part along `inward`, a hair proud of the
    /// surface so the cut opens cleanly. `tolerance` widens printed fits (per side).
    public func cutter(_ screw: MetricScrew, at point: Vec3, inward: Vec3, depth: Double, tolerance: Double = 0.0002) -> EditableMesh {
        let t = screw.table
        let lead = 0.0005
        func bore(_ diameter: Double, _ length: Double) -> EditableMesh {
            Threads.cylinder(radius: diameter / 2000 + tolerance, from: -lead, to: length, axis: inward, at: point)
        }
        switch self {
        case .clearance: return bore(t.clearance, depth)
        case .tapped: return bore(t.tap, depth)
        case .insert: return bore(t.insert, min(depth, t.insertDepth / 1000))
        case .counterbore:
            let head = bore(t.head + 1, t.headHeight / 1000)
            return (try? MeshBoolean.combine(bore(t.clearance, depth), head, .union)) ?? bore(t.clearance, depth)
        case .threaded:
            let thread = Threads.solid(major: screw.diameter + tolerance * 2, pitch: screw.pitch, length: depth + lead, fade: false)
            return thread.transformed(by: Transform(position: point - inward.normalized * lead,
                                                    rotation: Quat.rotation(from: .unitY, to: inward.normalized)))
        }
    }
}

/// Screw threads as solids (G1, Print): the ISO 60° profile wound into a right-hand helix up +y, its first and last
/// half turn faded into the core so the ends print clean. The same shape cuts a nut's thread, a little larger.
public enum Threads {
    /// The thread's surface: radius at angle `θ` (radians) and height `y` for a thread of `major` diameter and `pitch`.
    static func radius(major: Double, pitch: Double, at angle: Double, height y: Double, length: Double, fade: Bool) -> Double {
        let outer = major / 2, deep = 0.866_025 * pitch * 5 / 8
        let inner = outer - deep
        var s = (y - pitch * angle / (2 * .pi)).truncatingRemainder(dividingBy: pitch)
        if s < 0 { s += pitch }
        if s > pitch / 2 { s -= pitch }
        let crest = pitch / 16, flank = pitch / 2 - pitch / 8
        let r: Double = if abs(s) <= crest {
            outer
        } else if abs(s) <= flank {
            outer - (abs(s) - crest) / (flank - crest) * deep
        } else {
            inner
        }
        guard fade else { return r }
        let reach = min(y, length - y) / (pitch / 2)
        return inner + (r - inner) * min(max(reach, 0), 1)
    }

    /// A threaded rod `length` long standing on the origin up +y.
    public static func solid(major: Double, pitch: Double, length: Double, segments: Int = 48, fade: Bool = true) -> EditableMesh {
        let rowsPerPitch = 16
        let rows = max(Int((length / pitch * Double(rowsPerPitch)).rounded(.up)), 2)
        var points: [Vec3] = []
        for row in 0 ... rows {
            let y = length * Double(row) / Double(rows)
            for index in 0 ..< segments {
                let angle = 2 * Double.pi * Double(index) / Double(segments)
                let r = radius(major: major, pitch: pitch, at: angle, height: y, length: length, fade: fade)
                let edgeRadius = row == 0 || row == rows ? major / 2 - 0.866_025 * pitch * 5 / 8 : r
                points.append(Vec3(edgeRadius * sin(angle), y, edgeRadius * cos(angle)))
            }
        }
        var faces: [EditableMesh.Face] = []
        func at(_ row: Int, _ index: Int) -> Int { row * segments + (index % segments) }
        for row in 0 ..< rows {
            for index in 0 ..< segments {
                faces.append(EditableMesh.Face([at(row, index), at(row, index + 1), at(row + 1, index + 1)]))
                faces.append(EditableMesh.Face([at(row, index), at(row + 1, index + 1), at(row + 1, index)]))
            }
        }
        faces.append(EditableMesh.Face((0 ..< segments).map { at(0, $0) }.reversed()))
        faces.append(EditableMesh.Face((0 ..< segments).map { at(rows, $0) }))
        return outward(EditableMesh(vertices: points, faces: faces))
    }

    /// A cylinder of `radius` along `axis` from `from` to `to` (metres along it) past `point`.
    static func cylinder(radius: Double, from: Double, to: Double, axis: Vec3, at point: Vec3, segments: Int = 32) -> EditableMesh {
        let standing = EditableMesh.cylinder(base: Vec3(0, from, 0), radius: radius, height: to - from, segments: segments)
        return standing.transformed(by: Transform(position: point, rotation: Quat.rotation(from: .unitY, to: axis.normalized)))
    }

    /// Faces turned out (a closed mesh whose volume comes out negative is inside out).
    static func outward(_ mesh: EditableMesh) -> EditableMesh {
        guard mesh.volume < 0 else { return mesh }
        return EditableMesh(vertices: mesh.vertices, faces: mesh.faces.map { EditableMesh.Face(loops: $0.loops.map { $0.reversed() }) })
    }

    /// A hexagon's prism, `across` flats, `height` tall, standing on the origin.
    static func hex(across: Double, height: Double) -> EditableMesh {
        let r = across / sqrt(3)
        let outline = (0 ..< 6).map { index -> Vec3 in
            let angle = Double(index) / 6 * 2 * .pi + .pi / 6
            return Vec3(cos(angle) * r, 0, -sin(angle) * r)
        }
        return Prism.make(outline: outline, holes: [], normal: .unitY, from: 0, to: height)
    }

    // MARK: Things to print

    /// A hex bolt, head on the bed and the thread up: `length` of thread under the head (4 × its diameter by default).
    public static func bolt(_ screw: MetricScrew, length: Double? = nil, tolerance: Double = 0.0002) throws(MeshBoolean.Failure) -> EditableMesh {
        let t = screw.table
        let head = hex(across: t.hex / 1000, height: t.headHeight / 1000 * 0.7)
        let shank = length ?? screw.diameter * 4
        let thread = solid(major: screw.diameter - tolerance, pitch: screw.pitch, length: shank + 0.0005)
            .transformed(by: Transform(position: Vec3(0, t.headHeight / 1000 * 0.7 - 0.0005, 0)))
        return try MeshBoolean.combine(head, thread, .union)
    }

    /// A hex nut for the same size, its thread cut a fit larger.
    public static func nut(_ screw: MetricScrew, tolerance: Double = 0.0002) throws(MeshBoolean.Failure) -> EditableMesh {
        let t = screw.table
        let height = t.nut / 1000
        let body = hex(across: t.hex / 1000, height: height)
        let cutter = solid(major: screw.diameter + tolerance * 2, pitch: screw.pitch, length: height + 0.002, fade: false)
            .transformed(by: Transform(position: Vec3(0, -0.001, 0)))
        return try MeshBoolean.combine(body, cutter, .subtract)
    }

    /// A jar and its screw-on lid (Giulia's threaded lid): a jar `inside` across and `height` tall with `wall`s, a
    /// thread round its neck, and a lid that screws onto it, standing beside it upside down so both print as they are.
    public struct Jar: Sendable {
        public var inside: Double
        public var height: Double
        public var wall: Double
        public var pitch: Double
        public var tolerance: Double

        public init(inside: Double = 0.05, height: Double = 0.06, wall: Double = 0.0024, pitch: Double = 0.004, tolerance: Double = 0.0002) {
            self.inside = inside
            self.height = height
            self.wall = wall
            self.pitch = pitch
            self.tolerance = tolerance
        }

        /// How much of the neck is threaded, and the thread's depth.
        var threadLength: Double { pitch * 2.5 }
        var depth: Double { 0.866_025 * pitch * 5 / 8 }
        var outer: Double { inside / 2 + wall }
        /// The neck thread's diameter: its root sunk a little into the wall (a thread exactly on the wall would leave
        /// slivers where the two meet).
        var neck: Double { (outer + depth - 0.0003) * 2 }

        public func make() throws(MeshBoolean.Failure) -> (jar: EditableMesh, lid: EditableMesh) {
            let segments = 96
            let floor = wall
            let body = EditableMesh.cylinder(base: .zero, radius: outer, height: height, segments: segments)
            let thread = Threads.solid(major: neck, pitch: pitch, length: threadLength, segments: segments)
                .transformed(by: Transform(position: Vec3(0, height - threadLength - 0.001, 0)))
            let hollow = EditableMesh.cylinder(base: Vec3(0, floor, 0), radius: inside / 2, height: height, segments: segments)
            let jar = try MeshBoolean.combine(MeshBoolean.combine(body, thread, .union), hollow, .subtract)
            // The lid: a cap over the neck, its thread cut a fit larger, open side down while it's on the jar.
            let lidHeight = threadLength + wall + 0.002
            let lidOuter = outer + depth + tolerance + wall
            let cap = EditableMesh.cylinder(base: .zero, radius: lidOuter, height: lidHeight, segments: segments)
            let cutter = Threads.solid(major: neck + tolerance * 2, pitch: pitch, length: threadLength + 0.002, segments: segments,
                                       fade: false).transformed(by: Transform(position: Vec3(0, -0.001, 0)))
            let bore = EditableMesh.cylinder(base: Vec3(0, -0.001, 0), radius: outer + tolerance, height: lidHeight - wall + 0.001,
                                             segments: segments)
            var lid = try MeshBoolean.combine(MeshBoolean.combine(cap, cutter, .subtract), bore, .subtract)
            // Upside down beside the jar, top on the bed.
            lid = lid.transformed(by: Transform(position: Vec3(outer + lidOuter + 0.01, lidHeight, 0), rotation: Quat(angle: .pi, axis: .unitX)))
            return (jar, lid)
        }
    }
}
