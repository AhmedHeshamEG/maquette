import Foundation
import LoweyCore

/// What the Draw bar's Brush holds (U5, CONTEXT §10.11: lines in the air, colour on a surface, solids and shapes are
/// brush sets in one library): a library brush that draws lines, or one from a painting set that puts colour on a
/// model; a solid; a shape; the shadow brush.
enum DrawBrushKind: Equatable, Sendable {
    case lines
    case paint
    case solid(DrawingRecipe.Style)
    case shape(SketchKind)
    case shadow(pushes: Bool)

    /// The library brush is in the hand (lines or paint), not one of the making sets.
    var isLibraryBrush: Bool { self == .lines || self == .paint }

    var title: String {
        switch self {
        case .lines: "Lines"
        case .paint: "Paint"
        case let .solid(style): style.title
        case let .shape(kind): kind.title
        case let .shadow(pushes): pushes ? "Shadow in" : "Light out"
        }
    }

    var systemImage: String {
        switch self {
        case .lines: "pencil.tip"
        case .paint: "paintbrush"
        case let .solid(style): style.systemImage
        case let .shape(kind): kind.systemImage
        case let .shadow(pushes): pushes ? "circle.lefthalf.filled" : "sun.max"
        }
    }
}

/// The Draw bar's first three verbs (Procreate's): draw with the brush, smudge (lines are pushed into a new shape),
/// erase. The last two buttons, Sheets (or Layers) and Colour, open their own pop-overs.
enum DrawVerb: String, CaseIterable, Identifiable, Sendable {
    case brush, smudge, erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brush: "Brush"
        case .smudge: "Smudge"
        case .erase: "Erase"
        }
    }

    var systemImage: String {
        switch self {
        case .brush: "paintbrush.pointed"
        case .smudge: "hand.point.up.left.and.text"
        case .erase: "eraser"
        }
    }
}

/// The built-in sets that make things rather than hold library brushes, shown under the library's own sets.
enum DrawMakingSet: String, CaseIterable, Identifiable, Sendable {
    case solids, shapes, shadow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solids: "Solids"
        case .shapes: "Shapes"
        case .shadow: "Shadow"
        }
    }

    var kinds: [DrawBrushKind] {
        switch self {
        case .solids: DrawingRecipe.Style.solid.map { .solid($0) }
        case .shapes: SketchKind.allCases.map { .shape($0) }
        case .shadow: [.shadow(pushes: true), .shadow(pushes: false)]
        }
    }

    func contains(_ kind: DrawBrushKind) -> Bool { kinds.contains(kind) }
}

extension BrushSet {
    /// A set whose brushes put colour on a model (the built-in Painting set): with one in the hand, a stroke that starts
    /// on a thing paints it, and Sheets becomes Layers.
    var paintsSurfaces: Bool { id == "builtin.painting" }
}

extension DrawingRecipe.Style {
    /// The solid-shape styles (ink has its own tool).
    static let solid: [DrawingRecipe.Style] = [.tube, .ribbon, .extrude, .lathe]

    var title: String {
        switch self {
        case .tube: "Tube"
        case .ribbon: "Ribbon"
        case .extrude: "Extrude"
        case .lathe: "Lathe"
        case .ink: "Ink"
        }
    }

    var systemImage: String {
        switch self {
        case .tube: "scribble.variable"
        case .ribbon: "wave.3.right"
        case .extrude: "square.stack.3d.up"
        case .lathe: "rotate.3d"
        case .ink: "pencil.tip"
        }
    }

    var hint: String {
        switch self {
        case .tube: "Lines become round tubes."
        case .ribbon: "Flat strips on the sheet."
        case .extrude: "Draw a closed outline: it becomes a solid."
        case .lathe: "Draw half a profile: it spins into a vase, a trunk or a tower."
        case .ink: "Pencil lines in 3D that always face the camera."
        }
    }
}

extension DrawingGuide.Kind {
    var title: String {
        switch self {
        case .grid: "2D grid"
        case .isometric: "Isometric"
        case .perspective: "Perspective"
        case .symmetry: "Symmetry"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "grid"
        case .isometric: "cube"
        case .perspective: "road.lanes"
        case .symmetry: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        }
    }
}
