import Foundation

/// The hand shortcuts (CONTEXT §10.10): a small set that makes a practised hand fast, felt in the hand, with no
/// pop-up choices on screen. Each one can be switched off in Settings ▸ Gestures; they are on until then. Zooming
/// and touch-and-hold for options aren't here: they are how the apps work, not shortcuts.
public enum HmmShortcut: String, CaseIterable, Identifiable, Sendable {
    case undo
    case redo
    case hideChrome
    case editMenu
    case frame
    case snapWithFinger
    case cleanShape
    case squeeze
    case pencilDoubleTap

    public var id: String { rawValue }

    /// The gesture, in a few words.
    public var gesture: String {
        switch self {
        case .undo: "Two-finger tap"
        case .redo: "Three-finger tap"
        case .hideChrome: "Four-finger tap"
        case .editMenu: "Three-finger swipe down"
        case .frame: "Double-tap with a finger"
        case .snapWithFinger: "A finger held down while the Pencil works"
        case .cleanShape: "Hold at the end of a stroke"
        case .squeeze: "Squeeze the Pencil"
        case .pencilDoubleTap: "Double-tap the Pencil"
        }
    }

    /// What it does.
    public var meaning: String {
        switch self {
        case .undo: "Undo; hold to keep undoing"
        case .redo: "Redo; hold to keep redoing"
        case .hideChrome: "Hide or show everything but the canvas"
        case .editMenu: "Cut, copy and paste"
        case .frame: "Frame a thing; again, look straight at the face you touched"
        case .snapWithFinger: "Snapping flips for that one move"
        case .cleanShape: "The stroke becomes a clean line, arc or circle"
        case .squeeze: "The quick menu at the tip"
        case .pencilDoubleTap: "What the iPad's Pencil setting says (the eraser, the last tool, the colours)"
        }
    }

    public var storageKey: String { "hmm.shortcut.\(rawValue)" }

    /// On unless Settings switched it off.
    public func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? true
    }

    public func set(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: storageKey)
    }
}
