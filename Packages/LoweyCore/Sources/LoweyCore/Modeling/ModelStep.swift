import Foundation

/// One modelling step in a shape's editable history (H1): what was done, to which faces or edges (by their tags,
/// `PartTags`), with which numbers. Replaying the steps from the shape they started on gives the shape again, and
/// changing a step's numbers and replaying gives the shape as if it had been made that way.
public struct ModelStep: Codable, Hashable, Sendable {
    public enum Action: Codable, Hashable, Sendable {
        /// Faces moved along their normals (Push/pull).
        case pushPull(faces: [FaceRef], distance: Double)
        case inset(faces: [FaceRef], distance: Double)
        case bevel(edges: [EdgeRef], size: Double, style: EdgeBevel.Style)
        /// Hollowed to walls `thickness` thick, `open` faces left off.
        case shell(thickness: Double, open: [FaceRef])
        /// A sketch's area pulled out of the shape (positive) or cut into it (negative). The sketch is in the shape's
        /// own space and holds only the curves the area was made of. `through`: the cut went right through, and
        /// goes through again however thick the shape becomes. `onFace`: the face it was drawn on, which it follows.
        case sketch(SketchCut)
        /// Another solid, in the shape's own space, combined with it.
        case combine(tool: EditableMesh, operation: MeshBoolean.Operation)
    }

    public struct SketchCut: Codable, Hashable, Sendable {
        public var plane: PlaneFrame
        public var curves: [SketchCurve]
        public var region: Int
        public var distance: Double
        public var through: Bool
        public var onFace: FaceRef?

        public init(plane: PlaneFrame, curves: [SketchCurve], region: Int, distance: Double, through: Bool, onFace: FaceRef?) {
            self.plane = plane
            self.curves = curves
            self.region = region
            self.distance = distance
            self.through = through
            self.onFace = onFace
        }
    }

    /// Names the faces this step makes, so they keep their names when it replays.
    public var tag: PartTags.Tag
    public var action: Action
    /// Under live symmetry, the side kept (`true`: the axis's positive side) and the axis.
    public var symmetry: SymmetryAxis?
    public var keepsPositive: Bool

    public init(tag: PartTags.Tag, action: Action, symmetry: SymmetryAxis? = nil, keepsPositive: Bool = true) {
        self.tag = tag
        self.action = action
        self.symmetry = symmetry
        self.keepsPositive = keepsPositive
    }
}

// MARK: Numbers

/// A number of a step, in metres: what the steps list shows and lets you change.
public struct StepNumber: Hashable, Sendable {
    public enum Name: String, Sendable, CaseIterable {
        case distance, depth, size, radius, thickness, diameter, width, height

        public var title: String {
            switch self {
            case .distance: "Distance"
            case .depth: "Depth"
            case .size: "Size"
            case .radius: "Radius"
            case .thickness: "Thickness"
            case .diameter: "Diameter"
            case .width: "Width"
            case .height: "Height"
            }
        }
    }

    public var name: Name
    public var value: Double
    /// Push/pull and pulls go either way; everything else is a size.
    public var signed: Bool
}

public extension ModelStep {
    /// Every number the step has, in order.
    var numbers: [StepNumber] {
        switch action {
        case let .pushPull(_, distance): [StepNumber(name: .distance, value: distance, signed: true)]
        case let .inset(_, distance): [StepNumber(name: .distance, value: distance, signed: false)]
        case let .bevel(_, size, style): [StepNumber(name: style == .round ? .radius : .size, value: size, signed: false)]
        case let .shell(thickness, _): [StepNumber(name: .thickness, value: thickness, signed: false)]
        case let .sketch(cut): Self.numbers(of: cut)
        case .combine: []
        }
    }

    /// The step with number `index` set to `value` (metres).
    func setting(_ index: Int, to value: Double) -> ModelStep {
        var step = self
        switch action {
        case let .pushPull(faces, _): step.action = .pushPull(faces: faces, distance: value)
        case let .inset(faces, _): step.action = .inset(faces: faces, distance: max(value, 0))
        case let .bevel(edges, _, style): step.action = .bevel(edges: edges, size: max(value, 0), style: style)
        case let .shell(_, open): step.action = .shell(thickness: max(value, 0), open: open)
        case let .sketch(cut): step.action = .sketch(Self.setting(index, to: value, in: cut))
        case .combine: break
        }
        return step
    }

    /// "Hole, 6 mm", "Round, 2 mm", "Subtract": the step in plain words, with its first number.
    /// A sketch's step is named by the size of what was drawn ("Hole, 6 mm"), not by its depth.
    func title(format: (Double) -> String) -> String {
        let sizes = numbers.filter { $0.name != .depth && $0.name != .distance }
        let shown = if case .sketch = action, let size = sizes.first {
            size
        } else {
            numbers.first
        }
        guard let shown else { return name }
        return "\(name), \(format(shown.value))"
    }

    /// The step's name alone.
    var name: String {
        switch action {
        case .pushPull: "Push/pull"
        case .inset: "Inset"
        case let .bevel(_, _, style): style.label
        case .shell: "Shell"
        case let .sketch(cut):
            if cut.distance > 0 {
                "Pull"
            } else if cut.curves.count == 1, case .circle = cut.curves[0] {
                "Hole"
            } else { "Cut" }
        case let .combine(_, operation): operation.label
        }
    }

    // MARK: Sketch numbers

    /// The depth (unless it goes through), then each closed curve's size: a circle's diameter, a rectangle's sides.
    private static func numbers(of cut: SketchCut) -> [StepNumber] {
        var result: [StepNumber] = cut.through ? [] : [StepNumber(name: cut.distance > 0 ? .distance : .depth, value: abs(cut.distance), signed: false)]
        for curve in cut.curves {
            switch curve {
            case let .circle(_, radius): result.append(StepNumber(name: .diameter, value: radius * 2, signed: false))
            case let .rectangle(a, b):
                result.append(StepNumber(name: .width, value: abs(b.x - a.x), signed: false))
                result.append(StepNumber(name: .height, value: abs(b.y - a.y), signed: false))
            default: break
            }
        }
        return result
    }

    private static func setting(_ index: Int, to value: Double, in cut: SketchCut) -> SketchCut {
        var cut = cut
        var position = 0
        if !cut.through {
            if index == 0 {
                cut.distance = cut.distance > 0 ? max(value, 1e-6) : -max(value, 1e-6)
                return cut
            }
            position = 1
        }
        let size = max(value, 1e-6)
        for (curveIndex, curve) in cut.curves.enumerated() {
            switch curve {
            case let .circle(center, _):
                if index == position { cut.curves[curveIndex] = .circle(center: center, radius: size / 2) }
                position += 1
            case let .rectangle(a, b):
                let middle = (a + b) * 0.5
                let half = Vec2(abs(b.x - a.x), abs(b.y - a.y)) * 0.5
                if index == position {
                    cut.curves[curveIndex] = .rectangle(Vec2(middle.x - size / 2, middle.y - half.y), Vec2(middle.x + size / 2, middle.y + half.y))
                } else if index == position + 1 {
                    cut.curves[curveIndex] = .rectangle(Vec2(middle.x - half.x, middle.y - size / 2), Vec2(middle.x + half.x, middle.y + size / 2))
                }
                position += 2
            default: break
            }
        }
        return cut
    }
}
