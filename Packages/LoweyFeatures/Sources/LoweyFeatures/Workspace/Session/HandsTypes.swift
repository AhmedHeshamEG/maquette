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

/// The squeeze menu's six slots, each one of these (Settings ▸ Pencil and hands). U5: Lasso · Eyedropper · Eraser ↔ the
/// last brush · Snap · Hide the sheet and guides · Frame by default; Rig has its own six (`RigQuickAction`).
enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case lasso, eyedropper, eraser, snap, hideSheet, frame, lastTool, colour, undo, redo, play, hideChrome, newSheet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lasso: "Lasso"
        case .eyedropper: "Eyedropper"
        case .eraser: "Eraser or the last brush"
        case .snap: "Snapping"
        case .hideSheet: "Hide the sheet and guides"
        case .frame: "Frame the selection"
        case .lastTool: "Last tool"
        case .colour: "Colour"
        case .undo: "Undo"
        case .redo: "Redo"
        case .play: "Play"
        case .hideChrome: "Hide everything"
        case .newSheet: "New sheet"
        }
    }

    var systemImage: String {
        switch self {
        case .lasso: "lasso"
        case .eyedropper: "eyedropper"
        case .eraser: "eraser"
        case .snap: "magnet"
        case .hideSheet: "square.dashed"
        case .frame: "viewfinder"
        case .lastTool: "arrow.uturn.backward.circle"
        case .colour: "paintpalette"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .play: "play"
        case .hideChrome: "rectangle.dashed"
        case .newSheet: "square.on.square.dashed"
        }
    }

    static let storageKey = "quickMenuSlots.u5"
    /// Lasso, eyedropper, eraser ↔ last brush, snap, hide the sheet and guides, frame (CONTEXT §10.11).
    static let standard: [QuickAction] = [.lasso, .eyedropper, .eraser, .snap, .hideSheet, .frame]

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

/// The quick menu while Rig is in the hand (CONTEXT §10.11).
enum RigQuickAction: String, CaseIterable, Identifiable, Sendable {
    case pins, dots, mirrorPose, resetPose, savePose, showBones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pins: "Pins"
        case .dots: "Dots"
        case .mirrorPose: "Mirror the pose"
        case .resetPose: "Reset the pose"
        case .savePose: "Save the pose"
        case .showBones: "Show the bones"
        }
    }

    var systemImage: String {
        switch self {
        case .pins: "pin"
        case .dots: "circle.circle"
        case .mirrorPose: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .resetPose: "arrow.counterclockwise"
        case .savePose: "square.and.arrow.down"
        case .showBones: "figure.stand"
        }
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
