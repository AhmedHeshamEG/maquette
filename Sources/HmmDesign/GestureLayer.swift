/// The universal gestures of every hmm. app (listed identically in each Settings ▸ Gesture guide).
public enum HmmUniversalGesture: String, Sendable, CaseIterable, Identifiable {
    case undo, redo, rapidUndo, toggleChrome, zoom, options

    public var id: String { rawValue }

    public var gesture: String {
        switch self {
        case .undo: "Two-finger tap"
        case .redo: "Three-finger tap"
        case .rapidUndo: "Two-finger touch and hold"
        case .toggleChrome: "Four-finger tap"
        case .zoom: "Pinch"
        case .options: "Touch and hold on anything"
        }
    }

    public var meaning: String {
        switch self {
        case .undo: "Undo"
        case .redo: "Redo"
        case .rapidUndo: "Undo again and again, until you lift"
        case .toggleChrome: "Hide or show everything but the canvas"
        case .zoom: "Zoom the canvas"
        case .options: "Its options"
        }
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
    import SwiftUI
    import UIKit

    /// What the universal gestures do in one screen.
    @MainActor
    public struct HmmGestureActions {
        public var undo: () -> Void
        public var redo: () -> Void
        public var toggleChrome: () -> Void
        /// Three fingers swiped down: cut, copy and paste (nil: the screen has nothing to cut).
        public var editMenu: (() -> Void)?
        /// Seconds between steps while two (undo) or three (redo) fingers are held.
        public var rapidUndoInterval: Double

        public init(undo: @escaping () -> Void, redo: @escaping () -> Void, toggleChrome: @escaping () -> Void,
                    editMenu: (() -> Void)? = nil, rapidUndoInterval: Double = 0.12) {
            self.undo = undo
            self.redo = redo
            self.toggleChrome = toggleChrome
            self.editMenu = editMenu
            self.rapidUndoInterval = rapidUndoInterval
        }
    }

    /// Installs the universal finger gestures on the window that shows this view, next to (never instead of) the
    /// canvas's own gestures: touches still reach everything below, and the Pencil is never involved.
    public struct HmmGestureLayer: UIViewRepresentable {
        private let actions: HmmGestureActions

        public init(_ actions: HmmGestureActions) {
            self.actions = actions
        }

        public func makeUIView(context _: Context) -> InstallerView {
            let view = InstallerView()
            view.actions = actions
            view.isUserInteractionEnabled = false
            return view
        }

        public func updateUIView(_ view: InstallerView, context _: Context) {
            view.actions = actions
        }

        /// A zero-size view that owns the recognizers and moves them with its window.
        public final class InstallerView: UIView, UIGestureRecognizerDelegate {
            var actions: HmmGestureActions?
            private var recognizers: [UIGestureRecognizer] = []
            private weak var installedOn: UIWindow?
            private var repeatTimer: Timer?

            override public func didMoveToWindow() {
                super.didMoveToWindow()
                uninstall()
                if let window { install(on: window) }
            }

            private func install(on window: UIWindow) {
                let undo = tap(touches: 2, action: #selector(undoTapped))
                let redo = tap(touches: 3, action: #selector(redoTapped))
                let chrome = tap(touches: 4, action: #selector(chromeTapped))
                let hold = press(touches: 2, action: #selector(held(_:)))
                let redoHold = press(touches: 3, action: #selector(redoHeld(_:)))
                let swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.minimumNumberOfTouches = 3
                swipe.maximumNumberOfTouches = 3
                recognizers = [undo, redo, chrome, hold, redoHold, swipe]
                for recognizer in recognizers {
                    recognizer.cancelsTouchesInView = false
                    recognizer.delaysTouchesEnded = false
                    recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    recognizer.delegate = self
                    window.addGestureRecognizer(recognizer)
                }
                installedOn = window
            }

            private func uninstall() {
                stopRepeating()
                for recognizer in recognizers {
                    installedOn?.removeGestureRecognizer(recognizer)
                }
                recognizers.removeAll()
                installedOn = nil
            }

            private func tap(touches: Int, action: Selector) -> UITapGestureRecognizer {
                let recognizer = UITapGestureRecognizer(target: self, action: action)
                recognizer.numberOfTouchesRequired = touches
                return recognizer
            }

            private func press(touches: Int, action: Selector) -> UILongPressGestureRecognizer {
                let recognizer = UILongPressGestureRecognizer(target: self, action: action)
                recognizer.numberOfTouchesRequired = touches
                recognizer.minimumPressDuration = 0.55
                recognizer.allowableMovement = 12
                return recognizer
            }

            @objc private func undoTapped() {
                guard HmmShortcut.undo.isOn() else { return }
                HmmHaptics.play(.undo)
                actions?.undo()
            }

            @objc private func redoTapped() {
                guard HmmShortcut.redo.isOn() else { return }
                HmmHaptics.play(.undo)
                actions?.redo()
            }

            @objc private func chromeTapped() {
                guard HmmShortcut.hideChrome.isOn() else { return }
                HmmHaptics.play(.selection)
                actions?.toggleChrome()
            }

            /// Three fingers swiped down (and not sideways): the edit menu.
            @objc private func swiped(_ recognizer: UIPanGestureRecognizer) {
                guard recognizer.state == .ended, HmmShortcut.editMenu.isOn(), let editMenu = actions?.editMenu else { return }
                let travel = recognizer.translation(in: recognizer.view)
                guard travel.y > 60, abs(travel.x) < travel.y * 0.6 else { return }
                HmmHaptics.play(.selection)
                editMenu()
            }

            @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
                repeating(recognizer) { [weak self] in self?.undoTapped() }
            }

            @objc private func redoHeld(_ recognizer: UILongPressGestureRecognizer) {
                repeating(recognizer) { [weak self] in self?.redoTapped() }
            }

            /// Held still: the step once, then again and again until the fingers lift.
            private func repeating(_ recognizer: UILongPressGestureRecognizer, step: @escaping @MainActor () -> Void) {
                switch recognizer.state {
                case .began:
                    step()
                    stopRepeating()
                    let interval = actions?.rapidUndoInterval ?? 0.12
                    repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                        MainActor.assumeIsolated { step() }
                    }
                case .ended, .cancelled, .failed:
                    stopRepeating()
                default:
                    break
                }
            }

            private func stopRepeating() {
                repeatTimer?.invalidate()
                repeatTimer = nil
            }

            public func gestureRecognizer(_: UIGestureRecognizer,
                                          shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
                true
            }

            /// Text fields and sliders keep their own touches.
            public func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
                !(touch.view is UITextField || touch.view is UITextView)
            }
        }
    }

    public extension View {
        /// Adds the universal gestures (two-finger tap undo, three-finger tap redo, either held to repeat, four-finger tap
        /// hides the chrome, three fingers swiped down for cut, copy and paste) to this screen. Each obeys its switch in
        /// Settings ▸ Gestures (`HmmShortcut`).
        func hmmUniversalGestures(_ actions: HmmGestureActions) -> some View {
            background(HmmGestureLayer(actions).frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }
#endif
