import Foundation

/// Four legs and wings: the dots as marks (each named for its place), guessed or in a standard layout.
public extension BodyGuess {
    /// The marks a body shortcut starts from: guessed from the shape, or (nil from the guess) the standard layout.
    static func marks(_ body: Body, vertices: [Vec3], bounds: Bounds) -> (marks: [RigMark], guessed: Bool) {
        switch body {
        case .person:
            return ([], false)
        case .fourLegs:
            if let guessed = fourLegs(vertices, bounds: bounds) { return (guessed, true) }
            return (fourLegsLayout(bounds), false)
        case .wings:
            if let guessed = wings(vertices, bounds: bounds) { return (guessed, true) }
            return (wingsLayout(bounds), false)
        }
    }

    // MARK: Four legs

    /// An animal standing on four legs along its longer side, its head at the higher end.
    static func fourLegs(_ vertices: [Vec3], bounds: Bounds) -> [RigMark]? {
        let shape = Shape(vertices: vertices, bounds: bounds)
        guard let (columns, belly) = legs(shape, count: 4) else { return nil }
        let axis: Vec3 = bounds.size.x >= bounds.size.z ? .unitX : .unitZ
        let sorted = columns.sorted { $0[0].dot(axis) < $1[0].dot(axis) }
        let low = Array(sorted.prefix(2)), high = Array(sorted.suffix(2))
        let lowEnd = centre(low.map { $0[0] }).dot(axis), highEnd = centre(high.map { $0[0] }).dot(axis)
        func reach(beyond end: Double, sign: Double) -> [Vec3] { vertices.filter { ($0.dot(axis) - end) * sign > 0 } }
        let headHigh = (reach(beyond: highEnd, sign: 1).map(\.y).max() ?? -.infinity) >= (reach(beyond: lowEnd, sign: -1).map(\.y).max() ?? -.infinity)
        let (front, back) = headHigh ? (high, low) : (low, high)
        let forward = headHigh ? axis : axis * -1
        let bellyY = shape.ground + belly * shape.height
        func spineAt(_ pair: [[Vec3]]) -> Vec3 {
            let foot = centre(pair.map { $0[0] })
            let near = vertices.filter { abs(($0 - foot).dot(axis)) < bounds.size.dot(axis) * 0.1 }
            let top = near.map(\.y).max() ?? bounds.max.y
            return Vec3(foot.x * abs(axis.x) + bounds.center.x * abs(axis.z), (bellyY + top) / 2, foot.z * abs(axis.z) + bounds.center.z * abs(axis.x))
        }
        let hips = spineAt(back), shoulders = spineAt(front)
        var marks = [RigMark(name: "hips", kind: .dot, position: hips),
                     RigMark(name: "spine", kind: .dot, position: hips.lerp(to: shoulders, 0.5), parent: "hips"),
                     RigMark(name: "shoulders", kind: .dot, position: shoulders, parent: "spine")]
        let ahead = vertices.filter { $0.y > bellyY }.max { $0.dot(forward) < $1.dot(forward) } ?? shoulders + forward * 0.2
        marks.append(RigMark(name: "neck", kind: .dot, position: shoulders.lerp(to: ahead, 0.35), parent: "shoulders"))
        marks.append(RigMark(name: "head", kind: .dot, position: shoulders.lerp(to: ahead, 0.7), parent: "neck"))
        for (pair, top, end) in [(front, "shoulders", "front"), (back, "hips", "back")] {
            for column in pair {
                let side = (column[0] - hips).dot(forward.cross(.unitY)) > 0 ? "Right" : "Left"
                marks += leg(column, name: end + side, from: top, top: bellyY + shape.height * 0.05)
            }
        }
        if let tail = tail(vertices, from: hips, backward: forward * -1, length: bounds.size.dot(axis), above: bellyY) { marks += tail }
        return marks
    }

    /// A leg's top, knee and foot, hanging from `parent`.
    internal static func leg(_ column: [Vec3], name: String, from parent: String, top: Double) -> [RigMark] {
        let foot = column[0], knee = along(column, 0.5), hip = along(column, 1)
        return [RigMark(name: "\(name)Leg", kind: .dot, position: Vec3(hip.x, top, hip.z), parent: parent),
                RigMark(name: "\(name)Knee", kind: .dot, position: Vec3(knee.x, (top + foot.y) / 2, knee.z), parent: "\(name)Leg"),
                RigMark(name: "\(name)Foot", kind: .dot, position: foot, parent: "\(name)Knee")]
    }

    /// A tail behind the hips, when the shape goes on past them: a dot at its base, a pin at its tip.
    internal static func tail(_ vertices: [Vec3], from hips: Vec3, backward: Vec3, length: Double, above: Double) -> [RigMark]? {
        guard let tip = vertices.filter({ $0.y > above }).max(by: { $0.dot(backward) < $1.dot(backward) }),
              (tip - hips).dot(backward) > length * 0.25 else { return nil }
        return [RigMark(name: "tail", kind: .dot, position: hips.lerp(to: tip, 0.3), parent: "hips"),
                RigMark(name: "tailTip", kind: .pin, position: tip, parent: "tail")]
    }

    // MARK: Wings

    /// A winged creature spread across x, facing +z: the body is where it's thick, the wings where it thins out.
    static func wings(_ vertices: [Vec3], bounds: Bounds) -> [RigMark]? {
        let centreX = bounds.center.x
        let span = bounds.size.x / 2
        guard span > 0, let body = bodyHalfWidth(vertices, bounds: bounds), span > body * 2.5 else { return nil }
        let core = vertices.filter { abs($0.x - centreX) < body }
        let coreCentre = centre(core)
        let front = core.filter { $0.z >= coreCentre.z }, back = core.filter { $0.z < coreCentre.z }
        guard !front.isEmpty, !back.isEmpty, let headTip = core.max(by: { $0.z < $1.z }) else { return nil }
        let chest = centre(front), hips = centre(back)
        var marks = [RigMark(name: "chest", kind: .dot, position: chest),
                     RigMark(name: "neck", kind: .dot, position: chest.lerp(to: headTip, 0.5), parent: "chest"),
                     RigMark(name: "head", kind: .dot, position: chest.lerp(to: headTip, 0.85), parent: "neck"),
                     RigMark(name: "hips", kind: .dot, position: hips, parent: "chest")]
        if let tail = tail(core, from: hips, backward: Vec3(0, 0, -1), length: bounds.size.z, above: bounds.min.y) { marks += tail }
        for (side, sign) in [("left", 1.0), ("right", -1.0)] {
            let wing = vertices.filter { ($0.x - centreX) * sign > body }
            guard let tip = wing.max(by: { ($0.x - centreX) * sign < ($1.x - centreX) * sign }) else { return nil }
            let rootBand = wing.filter { ($0.x - centreX) * sign < body + span * 0.1 }
            let root = rootBand.isEmpty ? Vec3(centreX + sign * body, chest.y, chest.z) : centre(rootBand)
            let middle = root.lerp(to: tip, 0.5)
            let near = wing.filter { $0.distance(to: middle) < span * 0.12 }
            marks += [RigMark(name: "\(side)Wing", kind: .dot, position: root, parent: "chest"),
                      RigMark(name: "\(side)WingElbow", kind: .dot, position: near.count >= 3 ? centre(near) : middle, parent: "\(side)Wing"),
                      RigMark(name: "\(side)WingTip", kind: .dot, position: tip, parent: "\(side)WingElbow")]
        }
        return marks
    }

    /// Half the body's width: columns across x, from the middle out, until one is less than 40 % as tall as the middle.
    internal static func bodyHalfWidth(_ vertices: [Vec3], bounds: Bounds) -> Double? {
        let bins = 40
        let width = bounds.size.x / Double(bins)
        guard width > 0 else { return nil }
        var low = [Double](repeating: .infinity, count: bins), high = [Double](repeating: -.infinity, count: bins)
        for vertex in vertices {
            let index = min(max(Int((vertex.x - bounds.min.x) / width), 0), bins - 1)
            low[index] = min(low[index], vertex.y)
            high[index] = max(high[index], vertex.y)
        }
        let tall = (0 ..< bins).map { high[$0] > low[$0] ? high[$0] - low[$0] : 0 }
        let middle = bins / 2
        let core = tall[(middle - 2) ... (middle + 1)].max() ?? 0
        guard core > 0 else { return nil }
        var halves: [Double] = []
        for direction in [1, -1] {
            var index = middle
            while index >= 0, index < bins, tall[index] >= core * 0.4 {
                index += direction
            }
            halves.append(abs(bounds.min.x + (Double(index) + 0.5) * width - bounds.center.x))
        }
        return halves.reduce(0, +) / 2
    }

    // MARK: Standard layouts

    /// Four legs in the usual places of the box the thing fills, along its longer side, the head at +.
    static func fourLegsLayout(_ bounds: Bounds) -> [RigMark] {
        let along: Vec3 = bounds.size.x >= bounds.size.z ? .unitX : .unitZ
        let across = along.cross(.unitY)
        let length = bounds.size.dot(along), width = bounds.size.dot(across.absolute), height = bounds.size.y
        func at(_ forward: Double, _ side: Double, _ up: Double) -> Vec3 {
            bounds.center + along * (forward * length) + across * (side * width) + Vec3(0, bounds.min.y + up * height - bounds.center.y, 0)
        }
        var marks = [RigMark(name: "hips", kind: .dot, position: at(-0.3, 0, 0.62)),
                     RigMark(name: "spine", kind: .dot, position: at(0, 0, 0.64), parent: "hips"),
                     RigMark(name: "shoulders", kind: .dot, position: at(0.25, 0, 0.66), parent: "spine"),
                     RigMark(name: "neck", kind: .dot, position: at(0.36, 0, 0.8), parent: "shoulders"),
                     RigMark(name: "head", kind: .dot, position: at(0.45, 0, 0.9), parent: "neck")]
        for (end, forward, top) in [("front", 0.25, "shoulders"), ("back", -0.3, "hips")] {
            for (side, offset) in [("Left", -0.3), ("Right", 0.3)] {
                marks += [RigMark(name: "\(end)\(side)Leg", kind: .dot, position: at(forward, offset, 0.5), parent: top),
                          RigMark(name: "\(end)\(side)Knee", kind: .dot, position: at(forward, offset, 0.27), parent: "\(end)\(side)Leg"),
                          RigMark(name: "\(end)\(side)Foot", kind: .dot, position: at(forward, offset, 0.03), parent: "\(end)\(side)Knee")]
            }
        }
        return marks
    }

    /// Wings spread across x from a body in the middle, facing +z.
    static func wingsLayout(_ bounds: Bounds) -> [RigMark] {
        let c = bounds.center, size = bounds.size
        var marks = [RigMark(name: "chest", kind: .dot, position: c + Vec3(0, 0, size.z * 0.1)),
                     RigMark(name: "neck", kind: .dot, position: c + Vec3(0, size.y * 0.1, size.z * 0.3), parent: "chest"),
                     RigMark(name: "head", kind: .dot, position: c + Vec3(0, size.y * 0.15, size.z * 0.45), parent: "neck"),
                     RigMark(name: "hips", kind: .dot, position: c + Vec3(0, 0, -size.z * 0.2), parent: "chest")]
        for (side, sign) in [("left", 1.0), ("right", -1.0)] {
            marks += [RigMark(name: "\(side)Wing", kind: .dot, position: c + Vec3(sign * size.x * 0.1, 0, size.z * 0.1), parent: "chest"),
                      RigMark(name: "\(side)WingElbow", kind: .dot, position: c + Vec3(sign * size.x * 0.28, 0, size.z * 0.05), parent: "\(side)Wing"),
                      RigMark(name: "\(side)WingTip", kind: .dot, position: c + Vec3(sign * size.x * 0.48, 0, 0), parent: "\(side)WingElbow")]
        }
        return marks
    }
}

extension Vec3 {
    var absolute: Vec3 { Vec3(abs(x), abs(y), abs(z)) }
}
