import Foundation

/// One thing's own motion at any moment — its keys and behaviours (and, when asked, the links that move it) — evaluated
/// on a small scene of just the thing, its parents and what its behaviours follow, so a delayed copy or a driver's
/// turn can be read many times a frame.
struct SoloMotion {
    let id: ObjectID
    let document: Document
    let scene: Scene
    let tracks: Timeline
    let behaviors: [Behavior]
    let links: [MotionLink]
    let rates: FrameRates
    /// The stretch a loop plays (the loop region, else the timeline), and whether the thing meets itself over it.
    let range: TimeRange
    private(set) var repeats = false

    init(_ id: ObjectID, in document: Document, withLinks: Bool) {
        self.id = id
        self.document = document
        let timeline = document.scene.timeline
        behaviors = timeline.behaviors.filter { $0.enabled && $0.target == id }
        links = withLinks ? timeline.links.filter { $0.target == id } : []
        var keep = Set(document.scene.ancestors(of: id) + [id])
        for behavior in behaviors {
            keep.formUnion(Self.followed(by: behavior.kind))
        }
        var scene = document.scene
        scene.objects = scene.objects.filter { keep.contains($0.key) }
        self.scene = scene
        tracks = Timeline(fps: timeline.fps, duration: timeline.duration, stepping: timeline.stepping,
                          tracks: timeline.tracks.filter { keep.contains($0.target) })
        rates = FrameRates(document)
        range = timeline.loop ?? TimeRange(start: 0, end: timeline.duration)
        repeats = meetsItself(over: range)
    }

    /// What a behaviour looks at or moves with.
    static func followed(by kind: BehaviorKind) -> [ObjectID] {
        switch kind {
        case let .followPath(.object(path), _, _, _): [path]
        case let .lookAt(target), let .follow(target, _, _): [target]
        case let .orbit(_, around?, _, _): [around]
        default: []
        }
    }

    /// A moment `delay` seconds back from `time`. When the thing's motion repeats over the loop region (or the timeline),
    /// a moment before its start comes round from its end, so copies and links that wait play the motion as it repeats
    /// and a loop still meets itself; a motion that happens once rests before it starts.
    func earlier(_ time: Double, by delay: Double) -> Double {
        let moment = time - delay
        guard delay > 0, range.duration > 1e-6, moment < range.start, repeats else { return moment }
        return range.end - (range.start - moment).truncatingRemainder(dividingBy: range.duration)
    }

    /// Whether the thing stands the same at the end of `range` as at its start.
    private func meetsItself(over range: TimeRange) -> Bool {
        guard let first = transform(at: range.start), let last = transform(at: range.end) else { return false }
        return first.position.distance(to: last.position) < 1e-4 && abs(first.rotation.normalized.dot(last.rotation.normalized)) > 1 - 1e-8
            && (first.scale - last.scale).length < 1e-4
    }

    /// The thing's place in its parent's space at `time`.
    func transform(at time: Double) -> Transform? {
        var shown = scene
        var ignored = Set<ObjectID>()
        Animator.applyTracks(tracks, to: &shown, at: time, palette: document.palette, rates: rates, animated: &ignored)
        for behavior in behaviors {
            BehaviorEvaluator.apply(behavior, to: &shown, at: rates.sampleTime(time, for: id, in: shown)) { _, _ in nil }
        }
        if !links.isEmpty {
            // Drivers are read on their own, without their links, so two things linked both ways can't loop.
            MotionLinks.apply(links, to: &shown, document: document, time: time)
        }
        return shown.objects[id]?.transform
    }
}
