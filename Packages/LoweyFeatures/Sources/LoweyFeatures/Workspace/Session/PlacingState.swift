import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine
import Observation

/// What Q1 adds to the stage: the Reference window and the sheet laid on a face.
@Observable
@MainActor
final class PlacingState {
    /// The Reference window, nil until it's first opened in this project (`workspace.json`).
    var window: ReferenceWindow?
    /// A two-finger tap on the window hides it for a moment.
    var hidden = false
    /// The face under the hovering Pencil and the sheet's ghost on it, before a finger lays it.
    var ghost: SheetGhost?
    /// The last sheet laid on a face, for its chip's offset, turn and size.
    var fit: SheetFitState?
    /// The corner clusters' frames on screen, so the window settles off them.
    @ObservationIgnored var clusterFrames: [String: CGRect] = [:]
    /// The window's Canvas stage (its picking answers the eyedropper there).
    @ObservationIgnored weak var canvas: StageView?
    @ObservationIgnored var faceCache: SheetFaceCache?
    @ObservationIgnored var ghostTask: Task<Void, Never>?
    @ObservationIgnored var ghostSnapped = false
}

/// Where the sheet would go for a touch on a face.
struct FittedSheet {
    var sheet: DrawingSheet
    var placement: SheetFit.Placement
    var object: ObjectID
    var face: SheetFit.Face
    var mesh: MeshData
}

/// The ghost of the sheet on the face under the hovering Pencil (Q1): where a finger's tap there will lay it.
struct SheetGhost {
    var object: ObjectID
    var sheet: DrawingSheet
    /// The face lit, a hair above it, in world space.
    var lit: MeshData
}

/// The last sheet laid on a face, as it was laid: its chip's offset, turn and size are measured from there.
struct SheetFitState: Equatable {
    var sheetID: String
    var base: DrawingSheet
    var offset = 0.0
    var turn = 0.0
    var chipShown = true
}

/// The face found under the tip last, kept while the tip stays on it (finding a face scans the mesh).
struct SheetFaceCache {
    var object: ObjectID
    var revision: Int
    var face: SheetFit.Face
}
