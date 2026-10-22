import Foundation
import LoweyCore

/// The guest kits' working state (G1, `EditorModel+Guests`): what the set-ups' tools hold in the hand. It's how the
/// tools are set, not the project, so it's never undone.
struct GuestState: Sendable {
    /// Room: the roof the Roof tool lays, and its pitch.
    var roofKind: RoomParts.RoofKind = .gable
    var roofPitch = 30.0
    /// Room: the eye height a walk keeps (nil when not walking).
    var walkHeight: Double?
    /// Room: the drawing scale a PDF underlay was drawn at (1:100 is 0.01).
    var underlayScale = 0.01
    /// Room: setting an underlay to scale (the first tap, then the length typed).
    var scaling: UnderlayScaling?
    /// Print: the screw size and hole kind the Hole tool cuts, the words Engrave writes and how tall.
    var screw: MetricScrew = .m3
    var hole: ScrewHole = .clearance
    var text = "MAQUETTE"
    var textSize = 0.006
    /// Print: the fit between printed parts (per side), for pegs, threads and lids.
    var tolerance = 0.0002
    /// Print: faces that need support, shown in red.
    var overhangs = false
    /// Print: where Split cuts (across which axis, as a fraction of the part's size along it).
    var splitAxis: CoreAxis = .y
    var splitAt = 0.5
    /// Print: the wall Hollow leaves.
    var wall = 0.002
}

/// An underlay being set to scale: the thing, and the first point tapped on it.
struct UnderlayScaling: Sendable, Equatable {
    var object: ObjectID
    var first: Vec3?
    var second: Vec3?
}
