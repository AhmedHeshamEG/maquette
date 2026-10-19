import Foundation
import LoweyCore

/// What the next tap on the stage is for while motion design waits for a thing (D1).
enum DesignWait: Equatable {
    /// Tap the thing this one becomes.
    case morph(ObjectID)
    /// Tap the thing whose motion drives this one, in the way the preset says.
    case link(ObjectID, LinkPreset)

    var hint: String {
        switch self {
        case .morph: String(localized: "Tap the thing it becomes. Its shape is the one to reach.")
        case .link: String(localized: "Tap the thing whose motion moves it.")
        }
    }
}

/// Motion design's view state on the stage: what a tap is waiting for, and the sounds being measured.
struct DesignState {
    var wait: DesignWait?
    /// Audio clips whose loudness and beats are being measured in the background.
    var measuring: Set<String> = []
}

/// A ready-made link from the panel: what drives what, at what strength.
enum LinkPreset: String, CaseIterable, Identifiable {
    /// Turns as the other turns (−1: the other way, a gear).
    case turnWith, turnAgainst, moveWith, growWith

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turnWith: String(localized: "Turns with it")
        case .turnAgainst: String(localized: "Turns against it (a gear)")
        case .moveWith: String(localized: "Moves with it")
        case .growWith: String(localized: "Grows as it rises")
        }
    }

    var systemImage: String {
        switch self {
        case .turnWith: "arrow.clockwise"
        case .turnAgainst: "gearshape.2"
        case .moveWith: "arrow.up.and.down.and.arrow.left.and.right"
        case .growWith: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The link's channel, the driver's channel and the amount.
    var mapping: (channel: MotionLink.Channel, from: MotionLink.Channel, amount: Double) {
        switch self {
        case .turnWith: (.turnY, .turnY, 1)
        case .turnAgainst: (.turnY, .turnY, -1)
        case .moveWith: (.moveY, .moveY, 1)
        case .growWith: (.size, .moveY, 0.5)
        }
    }
}
