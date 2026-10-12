import Foundation

/// Who does what on the stage (CONTEXT §10.10, decided case by case; changed on one Settings page, as Procreate's
/// gesture controls are): moving objects and posing are the fingers', pulling a face, an edge or a corner is the
/// Pencil's. Drawing and painting follow Pencil or hand (`HmmPencilOrHand`), and moving the view is always fingers.
/// Until a Pencil has touched this iPad, a finger does the Pencil's jobs too.
enum InputJob: String, CaseIterable, Identifiable, Sendable {
    case move, shape, marks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: "Move objects and pose them"
        case .shape: "Pull faces, edges and corners"
        case .marks: "Place pins and dots"
        }
    }

    var standard: InputHand {
        switch self {
        case .move: .fingers
        case .shape, .marks: .pencil
        }
    }

    var storageKey: String { "inputJob.\(rawValue)" }

    var hand: InputHand {
        UserDefaults.standard.string(forKey: storageKey).flatMap(InputHand.init) ?? standard
    }

    /// Whether a touch may do this job: the Pencil when it's the Pencil's (or both's); a finger when it's the fingers'
    /// (or both's), or when no Pencil has been seen (`fingerMakes`) and nothing else could do it.
    func allows(pencil: Bool, fingerMakes: Bool) -> Bool {
        switch hand {
        case .both: true
        case .pencil: pencil || fingerMakes
        case .fingers: !pencil
        }
    }
}

enum InputHand: String, CaseIterable, Identifiable, Sendable {
    case fingers, pencil, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fingers: "Fingers"
        case .pencil: "Pencil"
        case .both: "Both"
        }
    }
}
