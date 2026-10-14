import Foundation
import LoweyCore

/// Model's bar (U6): at most six verbs. Shape is touch and drag (no buttons for faces, edges or corners); Brush is the
/// surface brushes; Cage pulls a box of points around the thing; Bend is the whole-shape bends; Measure measures.
enum ModelVerb: String, CaseIterable, Identifiable, Sendable {
    case shape, brush, cage, bend, measure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shape: "Shape"
        case .brush: "Brush"
        case .cage: "Cage"
        case .bend: "Bend"
        case .measure: "Measure"
        }
    }

    var systemImage: String {
        switch self {
        case .shape: "cube.transparent"
        case .brush: "hand.point.up.braille"
        case .cage: "square.grid.3x3.square"
        case .bend: "arrow.turn.up.right"
        case .measure: "ruler"
        }
    }

    /// One line on what it does, shown once while it's new (the instructions switch hides it).
    var hint: String {
        switch self {
        case .shape: "Touch a face, an edge or a corner with the Pencil and drag it. Tap one for more"
        case .brush: "Brush the surface: grab pulls it, smooth evens it, inflate puffs it up"
        case .cage: "Drag the cage's points to reshape the thing smoothly"
        case .bend: "Drag the handle to bend, twist, taper or bulge the thing"
        case .measure: "Tap the first point"
        }
    }
}

/// The surface brushes in the hand.
struct SculptSettings: Hashable, Sendable {
    var brush: SculptBrush = .grab
    /// Size on screen (points), the sidebar's first slider.
    var size: Double = 48
    /// 0…1, the sidebar's second slider.
    var strength: Double = 0.5
    /// Strokes mirror across the thing's middle (x).
    var symmetry = true
}

/// A sketch region waiting for one more pick before it becomes a solid.
enum ProfileWait: Hashable, Sendable {
    /// Tap a line or curve to sweep along.
    case sweep(SketchRegionRef)
    /// Tap a line to turn around (or Revolve again for the region's own left side).
    case revolve(SketchRegionRef)
    /// Tap more closed shapes, then Loft.
    case loft([SketchRegionRef])

    var hint: String {
        switch self {
        case .sweep: "Tap the path to sweep along"
        case .revolve: "Tap the line to turn around"
        case .loft: "Tap the next shape to loft through, then Loft"
        }
    }
}
