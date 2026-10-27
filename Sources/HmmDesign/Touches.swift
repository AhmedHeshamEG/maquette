#if canImport(UIKit)
    import Observation
    import UIKit

    // Lets the watcher fail once every touch is up, so it never claims one.
    // swiftlint:disable:next duplicate_imports
    import UIKit.UIGestureRecognizerSubclass

    /// Every touch that lands in the app's windows, fingers and the Pencil alike, counted (Maquette U5: a message leaves
    /// on any touch). The gesture layer (`HmmGestureLayer`) installs the watcher; nothing is claimed or delayed.
    @MainActor
    @Observable
    public final class HmmTouches {
        public static let shared = HmmTouches()

        /// Goes up by one each time a touch begins.
        public private(set) var count = 0
        /// The window the last touch landed in (the Pencil's haptics are played there).
        @ObservationIgnored public private(set) weak var window: UIWindow?

        public init() {}

        public func note(in window: UIWindow?) {
            count += 1
            if let window { self.window = window }
        }
    }

    /// A recogniser that only watches: it notes each touch as it begins and fails once every touch is up.
    final class HmmTouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        func configure() {
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
            HmmTouches.shared.note(in: touches.first?.window)
        }

        override func touchesEnded(_: Set<UITouch>, with event: UIEvent) {
            finishIfLifted(event)
        }

        override func touchesCancelled(_: Set<UITouch>, with event: UIEvent) {
            finishIfLifted(event)
        }

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
#endif

/// How many touches have begun so far (`HmmTouches`; always 0 where there is no touch screen). Read inside a view's
/// body, the view is updated on each new touch.
@MainActor
public enum HmmTouchCount {
    public static var now: Int {
        #if canImport(UIKit)
            HmmTouches.shared.count
        #else
            0
        #endif
    }
}
