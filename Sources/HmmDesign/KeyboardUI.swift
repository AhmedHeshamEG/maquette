#if canImport(SwiftUI) && canImport(UIKit)
    import SwiftUI
    import UIKit

    /// The keys in use, shared by the menu bar and Settings ▸ Keyboard. Observed: a key changed in Settings reaches the
    /// menu bar at once. While a key is being recorded every shortcut is off, so the press reaches the recorder.
    @MainActor @Observable
    public final class HmmKeyboard {
        public private(set) var bindings: HmmKeyBindings
        public let commands: [HmmKeyCommand]
        /// Settings is listening for a key.
        public var isRecording = false
        @ObservationIgnored private let defaults: UserDefaults

        public init(commands: [HmmKeyCommand], defaults: UserDefaults = .standard) {
            self.commands = commands
            self.defaults = defaults
            bindings = HmmKeyBindings.load(from: defaults)
        }

        public func combo(for command: HmmKeyCommand) -> HmmKeyCombo? {
            isRecording ? nil : bindings.combo(for: command)
        }

        /// The key shown beside a command in Settings (also while recording).
        public func shownCombo(for command: HmmKeyCommand) -> HmmKeyCombo? { bindings.combo(for: command) }

        /// Gives `command` a key; returns the commands that lost it.
        @discardableResult
        public func bind(_ command: HmmKeyCommand, to combo: HmmKeyCombo?) -> [HmmKeyCommand] {
            let losers = bindings.bind(command, to: combo, among: commands)
            bindings.save(to: defaults)
            return losers
        }

        @discardableResult
        public func reset(_ command: HmmKeyCommand) -> [HmmKeyCommand] {
            let losers = bindings.reset(command, among: commands)
            bindings.save(to: defaults)
            return losers
        }

        public func resetAll() {
            bindings = HmmKeyBindings()
            bindings.save(to: defaults)
        }
    }

    public extension HmmKeyCombo {
        var keyEquivalent: KeyEquivalent {
            switch key {
            case "delete": .delete
            case "escape": .escape
            case "return": .return
            case "tab": .tab
            case "space": .space
            case "up": .upArrow
            case "down": .downArrow
            case "left": .leftArrow
            case "right": .rightArrow
            default: KeyEquivalent(key.first ?? " ")
            }
        }

        var modifiers: EventModifiers {
            var result: EventModifiers = []
            if command { result.insert(.command) }
            if shift { result.insert(.shift) }
            if option { result.insert(.option) }
            if control { result.insert(.control) }
            return result
        }

        /// The combo of a key press (nil for a modifier on its own).
        init?(press key: UIKey) {
            let flags = key.modifierFlags
            guard let name = Self.name(of: key) else { return nil }
            self.init(name, command: flags.contains(.command), shift: flags.contains(.shift), option: flags.contains(.alternate),
                      control: flags.contains(.control))
        }

        /// Letters and digits by their place on the keyboard (⇧1 is "1", not "!"); other keys by what they type.
        private static func name(of key: UIKey) -> String? {
            let usage = key.keyCode.rawValue
            if (0x04 ... 0x1D).contains(usage) { return String(Character(UnicodeScalar(UInt8(0x61 + usage - 0x04)))) }
            if (0x1E ... 0x26).contains(usage) { return String(usage - 0x1E + 1) }
            if usage == 0x27 { return "0" }
            switch key.keyCode {
            case .keyboardDeleteOrBackspace: return "delete"
            case .keyboardEscape: return "escape"
            case .keyboardReturnOrEnter: return "return"
            case .keyboardTab: return "tab"
            case .keyboardSpacebar: return "space"
            case .keyboardUpArrow: return "up"
            case .keyboardDownArrow: return "down"
            case .keyboardLeftArrow: return "left"
            case .keyboardRightArrow: return "right"
            case .keyboardLeftShift, .keyboardRightShift, .keyboardLeftGUI, .keyboardRightGUI, .keyboardLeftAlt, .keyboardRightAlt,
                 .keyboardLeftControl, .keyboardRightControl, .keyboardCapsLock: return nil
            default:
                let typed = key.charactersIgnoringModifiers.lowercased()
                return typed.count == 1 ? typed : nil
            }
        }
    }

    public extension View {
        /// The command's key, as the person set it (none: no shortcut).
        func hmmKeyboardShortcut(_ command: HmmKeyCommand, in keyboard: HmmKeyboard) -> some View {
            modifier(HmmBoundShortcut(combo: keyboard.combo(for: command)))
        }
    }

    private struct HmmBoundShortcut: ViewModifier {
        let combo: HmmKeyCombo?

        func body(content: Content) -> some View {
            if let combo {
                content.keyboardShortcut(combo.keyEquivalent, modifiers: combo.modifiers)
            } else {
                content
            }
        }
    }

    /// Listens for one key press and hands it back (Settings ▸ Keyboard's "Press the new keys").
    public struct HmmKeyRecorder: UIViewRepresentable {
        private let pressed: (HmmKeyCombo) -> Void

        public init(pressed: @escaping (HmmKeyCombo) -> Void) {
            self.pressed = pressed
        }

        public func makeUIView(context _: Context) -> HmmKeyRecorderView {
            let view = HmmKeyRecorderView()
            view.pressed = pressed
            return view
        }

        public func updateUIView(_ view: HmmKeyRecorderView, context _: Context) {
            view.pressed = pressed
        }
    }

    public final class HmmKeyRecorderView: UIView {
        var pressed: ((HmmKeyCombo) -> Void)?

        override public var canBecomeFirstResponder: Bool { true }

        override public func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                if let key = press.key, let combo = HmmKeyCombo(press: key) {
                    pressed?(combo)
                    return
                }
            }
            super.pressesBegan(presses, with: event)
        }
    }
#endif
