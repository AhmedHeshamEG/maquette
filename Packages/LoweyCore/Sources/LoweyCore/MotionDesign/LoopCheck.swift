import Foundation

/// Whether a stretch loops seamlessly: the moment after its last frame (its end) looks exactly like its first. Every
/// thing's place, turn, size, colour, glow and opacity are compared at the two moments, copies from cloners and letters
/// of animated text included, so a loop that jumps is caught before it's exported, with what jumps named.
public enum LoopCheck {
    public struct Seam: Hashable, Sendable {
        public enum What: String, Sendable {
            case moves, turns, size, look, letters, physics

            public var title: String {
                switch self {
                case .moves: "moves"
                case .turns: "turns"
                case .size: "changes size"
                case .look: "changes colour or glow"
                case .letters: "letters don't meet"
                case .physics: "real things don't repeat"
                }
            }
        }

        public var object: ObjectID
        public var name: String
        public var what: What
    }

    /// What doesn't meet between `range.start` and `range.end` (empty: it loops).
    public static func seams(_ document: Document, range: TimeRange, rigs: [AssetID: RigAsset] = [:]) -> [Seam] {
        let first = Animator.evaluate(document, at: range.start, rigs: rigs).scene
        let last = Animator.evaluate(document, at: range.end, rigs: rigs).scene
        var seams: [Seam] = []
        for id in first.objects.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let a = first.objects[id], first.isEffectivelyVisible(id) || last.isEffectivelyVisible(id), a.cloneSource == nil,
                  let what = difference(id, first, last) else { continue }
            seams.append(Seam(object: id, name: a.name, what: what))
        }
        // A copy that jumps names its thing once.
        for id in first.objects.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let copy = first.objects[id], let source = copy.cloneSource, !seams.contains(where: { $0.object == source }),
                  let what = difference(id, first, last) else { continue }
            seams.append(Seam(object: source, name: document.scene.objects[source]?.name ?? copy.name, what: what))
        }
        for (id, object) in document.scene.objects.sorted(by: { $0.key.raw < $1.key.raw }) {
            if let letters = object.motionDesign?.letters, case let .text(recipe) = object.kind,
               !lettersMeet(letters, text: recipe, range: range) {
                seams.append(Seam(object: id, name: object.name, what: .letters))
            }
            if object.physics?.motion == .falls, !seams.contains(where: { $0.object == id }) {
                seams.append(Seam(object: id, name: object.name, what: .physics))
            }
        }
        return seams
    }

    static func difference(_ id: ObjectID, _ first: Scene, _ last: Scene) -> Seam.What? {
        guard let a = first.objects[id], let b = last.objects[id] else { return nil }
        let start = first.worldTransform(of: id), end = last.worldTransform(of: id)
        if start.position.distance(to: end.position) > 0.001 { return .moves }
        if abs(start.rotation.normalized.dot(end.rotation.normalized)) < cos(0.25 * .pi / 180) { return .turns }
        if (start.scale - end.scale).length > 0.001 { return .size }
        let looks: [PropertyKey] = [.color, .emissive, .emissiveIntensity, .opacity, .visible, .morph, .reveal]
        for key in looks where !same(a[key], b[key]) {
            return .look
        }
        return nil
    }

    private static func same(_ a: PropertyValue?, _ b: PropertyValue?) -> Bool {
        if let x = a?.floatValue, let y = b?.floatValue { return abs(x - y) < 1e-3 }
        return a == b
    }

    static func lettersMeet(_ letters: TextAnimator, text: TextRecipe, range: TimeRange) -> Bool {
        let count = TextAnimator.letterIndices(text.text).compactMap(\.self).count
        let a = letters.poses(count: count, at: range.start, size: text.size)
        let b = letters.poses(count: count, at: range.end, size: text.size)
        return zip(a, b).allSatisfy { lhs, rhs in
            lhs.offset.distance(to: rhs.offset) < 0.001 && (lhs.turn - rhs.turn).length < 0.25 && abs(lhs.scale - rhs.scale) < 1e-3
                && abs(lhs.opacity - rhs.opacity) < 1e-3
        }
    }
}
