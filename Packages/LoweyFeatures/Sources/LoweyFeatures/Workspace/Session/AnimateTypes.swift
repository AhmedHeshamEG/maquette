import CoreGraphics
import Foundation
import LoweyCore

/// What the Pencil does in Animate (A1). Nothing chosen: it picks, moves and poses things, and changes key themselves.
public enum AnimateVerb: String, CaseIterable, Identifiable, Sendable {
    /// Draw the way the selected thing goes: it follows at the speed it was drawn.
    case path
    /// Tap what the selected thing looks at (a character turns its head).
    case lookAt
    /// Tap the hand (or the thing) that takes the selected thing at the playhead; tap the ground to put it down.
    case pickUp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .path: "Path"
        case .lookAt: "Look at"
        case .pickUp: "Pick up"
        }
    }

    public var systemImage: String {
        switch self {
        case .path: "point.topleft.down.to.point.bottomright.curvepath"
        case .lookAt: "eye"
        case .pickUp: "hand.raised"
        }
    }

    /// The one line the stage shows while it's in the hand.
    public var hint: String {
        switch self {
        case .path: "Draw where it goes. It follows at the speed you draw."
        case .lookAt: "Tap what it looks at. Tap the empty ground and it stops looking."
        case .pickUp: "Tap the hand that takes it, at the playhead. Tap the empty ground to put it down."
        }
    }
}

/// Animate's state on the editor: on or off, the verb in the hand, how a drawn path moves its thing, the ghosts.
public struct AnimateState: Equatable, Sendable {
    public var isOn = false
    public var verb: AnimateVerb?
    /// A drawn path turns the thing to face the way it goes…
    public var facesTheWay = true
    /// …and leans it into its turns.
    public var banks = true
    /// Ghosts of past and future places while scrubbing (on by default).
    public var ghosts = true
    /// The path being drawn, on screen (the overlay draws it until the keys land).
    public var drawing: [CGPoint] = []
    /// The ruler is being dragged (the ghosts show while it is).
    public var scrubbing = false
    /// Motion rows or the dope sheet (remembered on the device).
    public var style = TimelineStyle(rawValue: UserDefaults.standard.string(forKey: TimelineStyle.key) ?? "") ?? .motion
    /// The path the Pencil is drawing, in the world, while it draws.
    var path: MotionDrawing?

    public init() {}
}

/// How the timeline shows its rows (A1): thick rows that show motion, or the dope sheet (every key of every property).
public enum TimelineStyle: String, CaseIterable, Identifiable, Sendable {
    case motion, dopeSheet

    static let key = "timeline.style"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .motion: "Motion"
        case .dopeSheet: "Dope sheet"
        }
    }
}
