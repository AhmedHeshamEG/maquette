#if canImport(UIKit)
    import QuartzCore
    import UIKit

    // Lets the touch watcher set its own state (it fails once every finger is up).
    // swiftlint:disable:next duplicate_imports
    import UIKit.UIGestureRecognizerSubclass

    /// The feel recorder (Diagnostics ▸ Record): for a while it watches every touch in the app's windows, the main
    /// thread's busy stretches and every refresh, and hands back a `FeelRecording`. It costs nothing until started and
    /// leaves nothing behind when it stops. Metal surfaces report their frames with `surfaceFrame`, so a touch on the
    /// stage is followed to the GPU; anything else is answered by the interface's next commit.
    @MainActor
    public final class FeelProbe {
        public private(set) static var current: FeelProbe?
        /// The last cold launch, process start to the first screen (seconds), once the app said so (`noteLaunched`).
        public private(set) static var launchSeconds: Double?

        public static var isRecording: Bool { current != nil }

        private var log: FeelLog
        private let screen: @MainActor () -> String
        private let finished: @MainActor (FeelRecording) -> Void
        private var link: CADisplayLink?
        private var observer: CFRunLoopObserver?
        private var watchers: [FeelTouchWatcher] = []
        private var busySince: Double?
        private var stopWork: DispatchWorkItem?

        private init(recording: FeelRecording, screen: @escaping @MainActor () -> String,
                     finished: @escaping @MainActor (FeelRecording) -> Void) {
            var recording = recording
            recording.launch = Self.launchSeconds.map { $0 * 1000 }
            log = FeelLog(start: CACurrentMediaTime(), recording: recording)
            self.screen = screen
            self.finished = finished
        }

        /// Starts recording for `seconds` (or until `stop`). `screen` says what is on screen, asked at each touch.
        public static func start(seconds: Double, recording: FeelRecording, screen: @escaping @MainActor () -> String,
                                 finished: @escaping @MainActor (FeelRecording) -> Void) {
            guard current == nil else { return }
            let probe = FeelProbe(recording: recording, screen: screen, finished: finished)
            current = probe
            probe.install()
            let work = DispatchWorkItem { MainActor.assumeIsolated { FeelProbe.stop() } }
            probe.stopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }

        /// Ends the recording now and hands it over.
        public static func stop() {
            guard let probe = current else { return }
            current = nil
            probe.uninstall()
            probe.finished(probe.log.finish(at: CACurrentMediaTime()))
        }

        /// A Metal surface finished a frame (call on the main thread once its command buffer completed). Times are
        /// `CACurrentMediaTime` seconds; the GPU's are the command buffer's own.
        public static func surfaceFrame(_ surface: UIView, started: Double, encoded: Double, gpuStart: Double, gpuEnd: Double) {
            guard let probe = current else { return }
            probe.log.surfaceFrame(.init(surface: surfaceKey(surface), started: started, encoded: encoded, gpuStart: gpuStart, gpuEnd: gpuEnd))
        }

        /// A named stretch (opening a project to its first frame…), `CACurrentMediaTime` seconds.
        public static func mark(_ name: String, from: Double, to: Double) {
            guard let probe = current else { return }
            probe.log.mark(name, from: from, to: to, screen: probe.screen())
        }

        /// The app shows its first screen: measures the cold launch from the process's start.
        public static func noteLaunched() {
            guard launchSeconds == nil, let started = processStart() else { return }
            launchSeconds = Date().timeIntervalSince(started)
        }

        // MARK: Watching

        private func install() {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                log.describeWindow(width: Double(window.bounds.width), height: Double(window.bounds.height))
            }
            for window in windows {
                let watcher = FeelTouchWatcher { [weak self] touches, phase in self?.received(touches, phase: phase) }
                window.addGestureRecognizer(watcher)
                watchers.append(watcher)
            }
            let link = CADisplayLink(target: FeelLinkTarget { [weak self] link in self?.tick(link) }, selector: #selector(FeelLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
            let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue
            // Last of the observers, so the interface's commit counts as the main thread's work.
            let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, CFIndex.max) { _, activity in
                MainActor.assumeIsolated { FeelProbe.current?.runLoop(activity) }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }

        private func uninstall() {
            stopWork?.cancel()
            for watcher in watchers {
                watcher.view?.removeGestureRecognizer(watcher)
            }
            watchers = []
            link?.invalidate()
            link = nil
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observer = nil
        }

        private func runLoop(_ activity: CFRunLoopActivity) {
            let now = CACurrentMediaTime()
            if activity == .afterWaiting {
                busySince = now
            } else {
                log.mainIdle(at: now, busySince: busySince, screen: screen())
                busySince = nil
            }
        }

        private func tick(_ link: CADisplayLink) {
            log.refresh(at: link.timestamp, period: link.targetTimestamp - link.timestamp, screen: screen())
            log.settle(at: CACurrentMediaTime())
        }

        private func received(_ touches: Set<UITouch>, phase: String) {
            guard let first = touches.first else { return }
            let delivered = CACurrentMediaTime()
            let point = first.location(in: first.window)
            let view = first.view
            log.deliver(.init(
                phase: phase, kind: touches.contains { $0.type == .pencil } ? "pencil" : "finger", count: touches.count,
                x: Double(point.x), y: Double(point.y), target: view.map(Self.typeName) ?? "none", screen: screen(),
                touched: touches.map(\.timestamp).max() ?? delivered, delivered: delivered,
                surface: view.flatMap(Self.metalSurface).map(Self.surfaceKey)
            ))
        }

        private static func typeName(_ view: UIView) -> String {
            let name = String(describing: type(of: view))
            return name.split(separator: "<").first.map(String.init) ?? name
        }

        /// The nearest view drawn by Metal at or above a view.
        private static func metalSurface(_ view: UIView) -> UIView? {
            sequence(first: view, next: \.superview).first { $0.layer is CAMetalLayer }
        }

        private static func surfaceKey(_ view: UIView) -> Int {
            ObjectIdentifier(view).hashValue
        }

        private static func processStart() -> Date? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        }
    }

    /// Sees every touch in its window and lets all of them through: it never recognises, never delays, never cancels.
    final class FeelTouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private let onTouches: @MainActor (Set<UITouch>, String) -> Void

        init(_ onTouches: @escaping @MainActor (Set<UITouch>, String) -> Void) {
            self.onTouches = onTouches
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouches(touches, "began")
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouches(touches, "moved")
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouches(touches, "ended")
            finishIfLifted(event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouches(touches, "cancelled")
            finishIfLifted(event)
        }

        /// Once every touch is up the watcher fails, so it is reset for the next touch like any recogniser.
        private func finishIfLifted(_ event: UIEvent) {
            let lifted = event.allTouches?.allSatisfy { $0.phase == .ended || $0.phase == .cancelled } ?? true
            if lifted { state = .failed }
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldBeRequiredToFailBy _: UIGestureRecognizer) -> Bool {
            false
        }
    }

    /// Lets a display link call a closure.
    final class FeelLinkTarget: NSObject {
        private let body: @MainActor (CADisplayLink) -> Void

        init(_ body: @escaping @MainActor (CADisplayLink) -> Void) {
            self.body = body
        }

        @MainActor @objc func tick(_ link: CADisplayLink) {
            body(link)
        }
    }
#endif
