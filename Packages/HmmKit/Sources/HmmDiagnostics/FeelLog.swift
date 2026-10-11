import Foundation

/// Builds a `FeelRecording` from what the probe sees. Pure arithmetic on one monotonic clock (seconds), so it is tested
/// on Linux: touches are held until the frame that answers them is known, then written with their time split up.
public struct FeelLog: Sendable {
    /// A touch delivered to the app, as the probe saw it.
    public struct Delivery: Sendable, Equatable {
        public var phase: String
        public var kind: String
        public var count: Int
        public var x: Double
        public var y: Double
        public var target: String
        public var screen: String
        /// The hardware's timestamp of the touch.
        public var touched: Double
        /// When the app received it.
        public var delivered: Double
        /// The Metal surface under the touch, if any (its frames answer it).
        public var surface: Int?

        public init(phase: String, kind: String, count: Int, x: Double, y: Double, target: String, screen: String,
                    touched: Double, delivered: Double, surface: Int? = nil) {
            self.phase = phase
            self.kind = kind
            self.count = count
            self.x = x
            self.y = y
            self.target = target
            self.screen = screen
            self.touched = touched
            self.delivered = delivered
            self.surface = surface
        }
    }

    /// A surface's frame: when it started building, finished encoding, and ran on the GPU.
    public struct Frame: Sendable, Equatable {
        public var surface: Int
        public var started: Double
        public var encoded: Double
        public var gpuStart: Double
        public var gpuEnd: Double

        public init(surface: Int, started: Double, encoded: Double, gpuStart: Double, gpuEnd: Double) {
            self.surface = surface
            self.started = started
            self.encoded = encoded
            self.gpuStart = gpuStart
            self.gpuEnd = gpuEnd
        }
    }

    private struct Pending {
        var delivery: Delivery
        var mainEnd: Double?
        var frame: Frame?
    }

    /// A touch on a surface that never redraws is answered by the interface after this long.
    public static let surfaceWait = 0.25
    /// The most touches one recording keeps (about four minutes of a moving Pencil at 120 Hz).
    public static let touchLimit = 30000

    public let start: Double
    public private(set) var recording: FeelRecording
    /// The newest refresh and the time between refreshes (from the display link).
    public private(set) var vsync: Double?
    public private(set) var period = 1.0 / 60.0
    private var pending: [Pending] = []

    public init(start: Double, recording: FeelRecording) {
        self.start = start
        self.recording = recording
    }

    public var pendingCount: Int { pending.count }

    public mutating func describeWindow(width: Double, height: Double) {
        recording.width = width
        recording.height = height
    }

    public mutating func deliver(_ delivery: Delivery) {
        guard recording.touches.count + pending.count < Self.touchLimit else { return }
        pending.append(Pending(delivery: delivery))
    }

    /// The main thread went idle: every touch it was working on has had its work done.
    public mutating func mainIdle(at time: Double, busySince: Double?, screen: String) {
        for index in pending.indices where pending[index].mainEnd == nil && pending[index].delivery.delivered <= time {
            pending[index].mainEnd = time
        }
        if let busySince, time - busySince > period * 1.5 {
            recording.stalls.append(.init(t: busySince - start, busy: (time - busySince) * 1000, screen: screen))
        }
    }

    /// A display-link tick: the refresh grid, and a hitch when it came later than one refresh after the last.
    public mutating func refresh(at timestamp: Double, period newPeriod: Double, screen: String) {
        if newPeriod > 0.001 { period = newPeriod }
        if let last = vsync, timestamp - last > period * 1.5 {
            recording.hitches.append(.init(t: last - start, gap: (timestamp - last) * 1000, screen: screen))
        }
        vsync = timestamp
        recording.refreshRate = (1 / period).rounded()
    }

    /// A surface finished a frame: the first touch on it delivered before the frame started takes it as its answer.
    public mutating func surfaceFrame(_ frame: Frame) {
        recording.frames.append(.init(t: frame.started - start, encode: (frame.encoded - frame.started) * 1000,
                                      gpu: (frame.gpuEnd - frame.gpuStart) * 1000))
        for index in pending.indices where pending[index].frame == nil && pending[index].delivery.surface == frame.surface
            && pending[index].delivery.delivered <= frame.started {
            pending[index].frame = frame
        }
    }

    public mutating func mark(_ name: String, from: Double, to: Double, screen: String) {
        recording.marks.append(.init(t: from - start, name: name, duration: (to - from) * 1000, screen: screen))
    }

    /// Writes every touch whose answer is known by `time`. `force` writes the rest as they stand (the end).
    public mutating func settle(at time: Double, force: Bool = false) {
        var waiting: [Pending] = []
        for item in pending {
            if let touch = written(item, at: time, force: force) {
                recording.touches.append(touch)
            } else {
                waiting.append(item)
            }
        }
        pending = waiting
    }

    public mutating func finish(at time: Double) -> FeelRecording {
        settle(at: time, force: true)
        recording.seconds = time - start
        recording.touches.sort { $0.t < $1.t }
        return recording
    }

    /// The first refresh after `time` on the display link's grid.
    public func nextRefresh(after time: Double) -> Double {
        guard let vsync else { return time }
        let steps = ((time - vsync) / period).rounded(.up)
        return vsync + max(steps, 0) * period
    }

    private func written(_ item: Pending, at time: Double, force: Bool) -> FeelRecording.Touch? {
        let delivery = item.delivery
        let mainEnd = item.mainEnd ?? (force ? time : nil)
        guard let mainEnd else { return nil }
        let frame = item.frame
        if frame == nil, delivery.surface != nil, !force, time - mainEnd < Self.surfaceWait { return nil }
        let ready = frame.map { max($0.gpuEnd, mainEnd) } ?? mainEnd
        let firstRefresh = nextRefresh(after: delivery.delivered)
        let missed = ready <= firstRefresh ? 0 : Int(((ready - firstRefresh) / period - 1e-6).rounded(.up))
        let mainWork = frame.map { min($0.started, mainEnd) } ?? mainEnd
        return FeelRecording.Touch(
            t: delivery.touched - start, phase: delivery.phase, kind: delivery.kind, count: delivery.count,
            x: delivery.x, y: delivery.y, target: delivery.target, screen: delivery.screen,
            input: (delivery.delivered - delivery.touched) * 1000,
            main: max(mainWork - delivery.delivered, 0) * 1000,
            encode: frame.map { ($0.encoded - $0.started) * 1000 },
            gpu: frame.map { ($0.gpuEnd - $0.gpuStart) * 1000 },
            total: (nextRefresh(after: ready) - delivery.touched) * 1000,
            missed: max(missed, 0)
        )
    }
}
