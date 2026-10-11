import CoreGraphics
import Foundation

/// The hand shortcuts' state on the stage (CONTEXT §10.10): the squeeze menu, the edit bar, the colours a shortcut
/// opened. View state, never saved.
struct HandsState: Equatable {
    /// Where the squeeze menu opened (screen points), while it is open.
    var quickMenuAt: CGPoint?
    /// Three fingers swiped down: cut, copy, paste.
    var editBar = false
    /// The colours, opened by the Pencil (the sidebar's well shows them).
    var choosingColour = false
}

/// What a squeeze or a double-tap of the Pencil does here.
enum PencilShortcut: Sendable {
    case eraser, lastTool, colour, quickMenu, none
}

/// The squeeze menu's six slots, each one of these (Settings ▸ Pencil and hands).
enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case eraser, lastTool, colour, snap, undo, redo, play, hideChrome, frame, newSheet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eraser: "Eraser"
        case .lastTool: "Last tool"
        case .colour: "Colour"
        case .snap: "Snapping"
        case .undo: "Undo"
        case .redo: "Redo"
        case .play: "Play"
        case .hideChrome: "Hide everything"
        case .frame: "Frame the selection"
        case .newSheet: "New sheet"
        }
    }

    var systemImage: String {
        switch self {
        case .eraser: "eraser"
        case .lastTool: "arrow.uturn.backward.circle"
        case .colour: "paintpalette"
        case .snap: "magnet"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .play: "play"
        case .hideChrome: "rectangle.dashed"
        case .frame: "viewfinder"
        case .newSheet: "square.on.square.dashed"
        }
    }

    static let storageKey = "quickMenuSlots"
    /// Eraser, last tool, colour, snap, undo, redo (CONTEXT §10.10).
    static let standard: [QuickAction] = [.eraser, .lastTool, .colour, .snap, .undo, .redo]

    /// The six slots as Settings left them.
    static func slots(in defaults: UserDefaults = .standard) -> [QuickAction] {
        guard let raw = defaults.string(forKey: storageKey) else { return standard }
        let slots = raw.split(separator: ",").compactMap { QuickAction(rawValue: String($0)) }
        return slots.count == standard.count ? slots : standard
    }

    static func save(_ slots: [QuickAction], in defaults: UserDefaults = .standard) {
        defaults.set(slots.map(\.rawValue).joined(separator: ","), forKey: storageKey)
    }
}

/// What a double-tap of the Pencil does (Settings ▸ Pencil and hands): what the iPad's Pencil setting says, or the
/// squeeze menu (for a Pencil that can't squeeze), or nothing.
enum DoubleTapChoice: String, CaseIterable, Identifiable, Sendable {
    case system, quickMenu, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "As the iPad's Pencil setting says"
        case .quickMenu: "The quick menu"
        case .off: "Nothing"
        }
    }

    static let storageKey = "pencilDoubleTap"

    static var current: DoubleTapChoice {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DoubleTapChoice.init) ?? .system
    }
}
