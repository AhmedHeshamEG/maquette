import Foundation

/// A pin or a dot placed on a thing to rig it (rig space, rest pose). **Dots** are joints: the thing bends at each
/// and is stiff between them, and pulling one brings its whole limb along (tap a shoulder, an elbow, a wrist).
/// **Pins** are for soft things: the stretch between a pin and the mark it hangs from bends smoothly, and pulling a
/// pin bends only that stretch, the mark above it holding still (a tail, a rope, an ear).
public struct RigMark: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case dot, pin
    }

    /// The joint it makes (pins also make the joints of their stretch, `RigMarks.between`).
    public var name: String
    public var kind: Kind
    public var position: Vec3
    /// The mark it hangs from (nil for the first).
    public var parent: String?
    /// How thick the part is there (0 when unknown: a drawing, a mark dragged off the thing).
    public var thickness: Double

    public var id: String { name }

    public init(name: String, kind: Kind, position: Vec3, parent: String? = nil, thickness: Double = 0) {
        self.name = name
        self.kind = kind
        self.position = position
        self.parent = parent
        self.thickness = thickness
    }

    private enum CodingKeys: String, CodingKey { case name, kind, position, parent, thickness }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .dot
        position = try c.decode(Vec3.self, forKey: .position)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0
    }
}

/// Building a skeleton from pins and dots, and changing the marks: every change gives new marks, and the skeleton is
/// built from them again (`rig`). Joints keep their marks' names, so poses and keys survive a mark being moved,
/// added or taken away (the joints of a mark that's gone go with it).
public enum RigMarks {
    /// The bones of a pin's stretch: it bends smoothly over this many.
    public static let pinSteps = 3
    /// The joint that carries the body when the marks don't cover it (`rig`).
    public static let rootName = "root"

    /// The `step`th joint of a pin's stretch (0 sits on the mark above it, so pulling the pin turns only its stretch).
    public static func between(_ pin: String, _ step: Int) -> String { "\(pin)~\(step)" }

    /// Whether a joint is one of a pin's in-between joints (never shown, never a handle of its own).
    public static func isBetween(_ joint: String) -> Bool { joint.contains("~") }

    /// The skeleton the marks make, in rig space. Each mark is a joint named as it is; a pin with a mark above it
    /// gets `pinSteps` bones between them. `surface` is every vertex of the thing (rig space): where the marks
    /// leave a body uncovered (a tail pinned on a cat), a joint named `root` in the middle of that body carries it,
    /// so the body holds still while the marks bend. A mark named `root` (a group's held part) stands for it.
    public static func rig(_ marks: [RigMark], surface: [Vec3]) -> ObjectRig {
        let ordered = parentsFirst(marks)
        var names: [String] = []
        var parents: [Int?] = []
        var positions: [Vec3] = []
        func add(_ name: String, parent: String?, at position: Vec3) {
            names.append(name)
            parents.append(parent.flatMap { names.firstIndex(of: $0) })
            positions.append(position)
        }
        let root = ordered.contains { $0.name == rootName } ? nil : bodyCentre(ordered, surface: surface)
        if let root { add(rootName, parent: nil, at: root) }
        for mark in ordered {
            let above = mark.parent.flatMap { name in ordered.first { $0.name == name } }
            if mark.kind == .pin, let above {
                var previous = above.name
                for step in 0 ..< pinSteps {
                    let name = between(mark.name, step)
                    add(name, parent: previous, at: above.position.lerp(to: mark.position, Double(step) / Double(pinSteps)))
                    previous = name
                }
                add(mark.name, parent: previous, at: mark.position)
            } else {
                add(mark.name, parent: above?.name ?? (root == nil ? nil : rootName), at: mark.position)
            }
        }
        return ObjectRig(names: names, parents: parents, positions: positions, standard: .custom, marks: ordered)
    }

    /// Marks sorted so every mark comes after the one it hangs from (a mark whose parent is missing becomes a first).
    public static func parentsFirst(_ marks: [RigMark]) -> [RigMark] {
        let names = Set(marks.map(\.name))
        var result: [RigMark] = []
        var placed = Set<String>()
        var left = marks.map { mark -> RigMark in
            var fixed = mark
            if let parent = mark.parent, !names.contains(parent) || parent == mark.name { fixed.parent = nil }
            return fixed
        }
        while !left.isEmpty {
            let ready = left.filter { $0.parent.map(placed.contains) ?? true }
            // A loop of marks (none ready): the first of them lets go.
            let next = ready.isEmpty ? [left[0]].map { mark -> RigMark in
                var free = mark
                free.parent = nil
                return free
            } : ready
            result += next
            placed.formUnion(next.map(\.name))
            let taken = Set(next.map(\.name))
            left.removeAll { taken.contains($0.name) }
        }
        return result
    }

    /// The bones between marks (each mark to the one above it), rig space.
    public static func segments(_ marks: [RigMark]) -> [(head: Vec3, tail: Vec3)] {
        let byName = Dictionary(marks.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return marks.compactMap { mark in mark.parent.flatMap { byName[$0] }.map { ($0.position, mark.position) } }
    }

    /// The middle of what the marks leave uncovered, when there's enough of it and it's away from the first mark.
    static func bodyCentre(_ marks: [RigMark], surface: [Vec3]) -> Vec3? {
        guard let first = marks.first, surface.count >= 8 else { return nil }
        let bones = segments(marks).map { BoneSegment(joint: 0, head: $0.head, tail: $0.tail) }
            + marks.map { BoneSegment(joint: 0, head: $0.position, tail: $0.position) }
        let size = Bounds(points: surface)?.size.length ?? 1
        let thicknesses = marks.map(\.thickness).filter { $0 > 0 }.sorted()
        let length = segments(marks).reduce(0) { $0 + $1.head.distance(to: $1.tail) }
        let thickness = thicknesses.isEmpty ? max(length / 6, size * 0.05) : thicknesses[thicknesses.count / 2]
        let reach = thickness * 1.5
        var total = Vec3.zero
        var count = 0
        for vertex in surface where bones.allSatisfy({ $0.distance(to: vertex) > reach }) {
            total += vertex
            count += 1
        }
        guard count >= max(8, surface.count / 50) else { return nil }
        let centre = total / Double(count)
        return centre.distance(to: first.position) > thickness * 0.5 ? centre : nil
    }

    // MARK: Changing the marks

    /// A fresh mark name ("j1", "j2", …) that no joint or mark uses.
    public static func newName(in marks: [RigMark], avoiding used: Set<String> = []) -> String {
        let taken = used.union(marks.map(\.name)).union([rootName])
        var index = marks.count + 1
        while taken.contains("j\(index)") {
            index += 1
        }
        return "j\(index)"
    }

    /// The marks with one more, hanging from `parent` (the first mark hangs from nothing).
    public static func adding(_ kind: RigMark.Kind, at position: Vec3, thickness: Double = 0, to parent: String?,
                              in marks: [RigMark]) -> (marks: [RigMark], name: String) {
        let name = newName(in: marks)
        let above = parent.flatMap { name in marks.contains { $0.name == name } ? name : nil } ?? marks.last?.name
        return (marks + [RigMark(name: name, kind: kind, position: position, parent: above, thickness: thickness)], name)
    }

    /// The marks with `name` moved (rig space).
    public static func moving(_ name: String, to position: Vec3, thickness: Double? = nil, in marks: [RigMark]) -> [RigMark] {
        marks.map { mark in
            guard mark.name == name else { return mark }
            var moved = mark
            moved.position = position
            if let thickness { moved.thickness = thickness }
            return moved
        }
    }

    /// The marks without `name`: what hung from it hangs from the mark above it; a first mark's place goes to the
    /// first that hung from it, and the others hang from that one.
    public static func removing(_ name: String, from marks: [RigMark]) -> [RigMark] {
        guard let gone = marks.first(where: { $0.name == name }) else { return marks }
        var result = marks.filter { $0.name != name }
        let orphans = result.indices.filter { result[$0].parent == name }
        if let above = gone.parent {
            for index in orphans {
                result[index].parent = above
            }
        } else if let heir = orphans.first {
            result[heir].parent = nil
            for index in orphans.dropFirst() {
                result[index].parent = result[heir].name
            }
        }
        return result
    }

    /// The marks with `name` turned into the other kind.
    public static func setting(_ name: String, to kind: RigMark.Kind, in marks: [RigMark]) -> [RigMark] {
        marks.map { mark in
            guard mark.name == name else { return mark }
            var changed = mark
            changed.kind = kind
            return changed
        }
    }

    /// The marks a rig can be changed with: its own, or (a rig from before 0.14) its joints read as dots, leaving out
    /// the root it made for the body (it's made again) and a pin's in-between joints.
    public static func marks(of rig: ObjectRig) -> [RigMark] {
        guard rig.marks.isEmpty else { return rig.marks }
        let rest = rig.restPositions
        let joints = rig.skeleton.joints
        func isMadeRoot(_ index: Int) -> Bool {
            joints[index].parent == nil && joints[index].name == rootName && rig.skeleton.children(of: index).count >= 1
        }
        func shownParent(_ index: Int) -> String? {
            var current = joints[index].parent
            while let parent = current {
                if !isMadeRoot(parent), !isBetween(joints[parent].name) { return joints[parent].name }
                current = joints[parent].parent
            }
            return nil
        }
        return joints.indices.compactMap { index in
            guard !isMadeRoot(index), !isBetween(joints[index].name) else { return nil }
            return RigMark(name: joints[index].name, kind: .dot, position: rest[index], parent: shownParent(index))
        }
    }
}
