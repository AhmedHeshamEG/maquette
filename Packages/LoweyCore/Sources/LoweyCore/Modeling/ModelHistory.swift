import Foundation

/// A modelled shape's editable history (H1, D-327): the shape it started from and every modelling step since, each
/// with its numbers. Change an early step's numbers and the steps after it replay on the changed shape.
///
/// It lives on the object (`SceneObject.modelHistory`) and is kept true by the modelling commands themselves: each
/// recorded tool runs as a `ModelStep`, so the shape the steps make is the shape the object has. When the shape changes
/// some other way (a knife, a corner dragged, clean up, a scale baked in), the next recorded step starts again from
/// that shape and the steps before it become `earlier`: listed, but fixed. Painting or rigging a shape fixes its
/// history at that point too (paint and rigs aren't parametric).
public struct ModelHistory: Codable, Hashable, Sendable {
    /// The shape the steps start from, in the object's own space.
    public var base: EditableMesh
    public var steps: [ModelStep]
    /// Steps before a change the history can't replay: listed, but fixed.
    public var earlier: [ModelStep]
    /// The tags of the faces of the shape the steps make.
    public var tags: [PartTags.Tag]
    /// `PartTags.shapeKey` of that shape: when the object's shape is something else, the history is out of date.
    public var shape: PartTags.Tag

    public init(base: EditableMesh, steps: [ModelStep] = [], earlier: [ModelStep] = [], tags: [PartTags.Tag], shape: PartTags.Tag) {
        self.base = base
        self.steps = steps
        self.earlier = earlier
        self.tags = tags
        self.shape = shape
    }

    /// A history starting from a shape, with nothing done to it yet.
    public init(starting mesh: EditableMesh, earlier: [ModelStep] = []) {
        self.init(base: mesh, earlier: earlier, tags: PartTags.base(count: mesh.faces.count), shape: PartTags.shapeKey(mesh))
    }

    /// The history still makes this shape, so its steps can be changed.
    public func describes(_ mesh: EditableMesh) -> Bool {
        shape == PartTags.shapeKey(mesh) && tags.count == mesh.faces.count
    }

    /// Every step's title, the fixed ones first.
    public func titles(format: (Double) -> String) -> [String] {
        (earlier + steps).map { $0.title(format: format) }
    }

    /// A new step's tag: different for every step a history ever holds.
    var nextTag: PartTags.Tag {
        PartTags.derive(shape, PartTags.Tag(earlier.count + steps.count + 1))
    }

    mutating func append(_ step: ModelStep, making shape: ModelStep.Shape) {
        steps.append(step)
        tags = shape.tags
        self.shape = PartTags.shapeKey(shape.mesh)
    }

    // MARK: Replay

    /// Why a replay stopped: which step, and why, in one line.
    public struct ReplayFailure: Error, Equatable, CustomStringConvertible {
        public var step: Int
        public var title: String
        public var reason: ModelingOperations.Failure

        public var description: String {
            "Step \(step + 1), \(title), can't follow the change: \(reason.description)"
        }
    }

    /// The shape with step `index` replaced by `step` and every step after it replayed, and the history that makes it.
    public func replaying(_ index: Int, as step: ModelStep, format: (Double) -> String = { "\($0)" })
        throws(ReplayFailure) -> (shape: EditableMesh, history: ModelHistory) {
        var changed = steps
        guard changed.indices.contains(index) else {
            throw ReplayFailure(step: earlier.count + index, title: "", reason: .partLost)
        }
        changed[index] = step
        var shape = ModelStep.Shape(mesh: base, tags: PartTags.base(count: base.faces.count))
        for (position, current) in changed.enumerated() {
            do {
                shape = try current.apply(to: shape)
            } catch {
                throw ReplayFailure(step: earlier.count + position, title: current.title(format: format), reason: error)
            }
        }
        var history = self
        history.steps = changed
        history.tags = shape.tags
        history.shape = PartTags.shapeKey(shape.mesh)
        return (shape.mesh, history)
    }
}
