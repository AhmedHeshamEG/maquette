import CoreGraphics
import Foundation
import HmmLink
import LoweyCore
import Observation

/// What Present mode plays (U8).
enum PresentKind: String, CaseIterable, Identifiable, Sendable {
    /// The film from the start, through its shots, again and again.
    case film
    /// Walking through at eye height (a building).
    case walk
    /// The model, turned by fingers, with nothing else on screen.
    case look

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: "Play the film"
        case .walk: "Walk through"
        case .look: "Show the model"
        }
    }

    var systemImage: String {
        switch self {
        case .film: "play.rectangle"
        case .walk: "figure.walk"
        case .look: "rotate.3d"
        }
    }
}

/// Presenting: what plays, and whether the presenter's few controls are showing (they fade after a moment).
struct PresentState: Equatable, Sendable {
    var kind: PresentKind
    var controls = true
}

/// A note being written: where it will sit and the words so far.
struct NoteDraft: Equatable, Sendable {
    var world: Vec3
    var object: ObjectID?
    var text = ""
}

/// The iPhone beside the iPad, once it has said hello.
struct CompanionPhone: Equatable, Sendable {
    var name: String
    var abilities: CompanionAbilities
}

/// U8's state on the editor: presenting, review notes, a review over FaceTime and the iPhone companion. One object, so
/// the editor's own list stays short; views read through it and follow its changes.
@MainActor @Observable
final class TogetherState {
    var presenting: PresentState?
    /// The film was paused by hand (it doesn't start round again by itself).
    var presentPaused = false
    /// The pins are on the stage (Actions ▸ Notes, and always during a review).
    var notesShown = false
    /// The next tap on the stage places a note.
    var placingNote = false
    var draft: NoteDraft?
    /// The note whose thread is open beside its pin.
    var openNote: String?
    /// In a review over FaceTime, and with how many people (this iPad included).
    var reviewing = false
    var reviewPeople = 0
    /// The iPhone companion: who joined, how the link stands, and what the iPad asked of it.
    var phone: CompanionPhone?
    var phoneLink: HmmLinkState = .off
    var asked: CompanionMode?
    /// Your iPhone sheet (Actions ▸ Your iPhone).
    var showsPhone = false

    @ObservationIgnored var host: HmmLinkHost?
    /// Where the scene's camera was when the iPhone took it (its moves are added to this).
    @ObservationIgnored var phoneCameraStart: (camera: ObjectID, pose: Transform)?
    @ObservationIgnored var lead = ViewLead()
    @ObservationIgnored var viewSequence = 0
    @ObservationIgnored var lastViewSent: CFTimeInterval = 0
    @ObservationIgnored var controlsTask: Task<Void, Never>?

    init() {}
}
