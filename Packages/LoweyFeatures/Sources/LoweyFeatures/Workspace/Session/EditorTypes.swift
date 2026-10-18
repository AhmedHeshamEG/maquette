import Foundation
import LoweyCore
import LoweyEngine

/// What a touch on the stage does (fingers always navigate unless a tool says otherwise).
public enum StageTool: String, CaseIterable, Identifiable, Sendable {
    /// Tap to select, drag a selection to move it, gizmo handles.
    case select
    /// Draw a loop around things to select them.
    case lasso
    /// Ink strokes: pressure lines in 3D that always face the camera (draw, erase, select strokes).
    case ink
    /// Solid shapes drawn in 3D (tube, ribbon, extrude, lathe) on the sheet.
    case draw
    /// Paint shadow shapes onto a surface (push the shadow in or pull it out).
    case shadowBrush
    /// Frame-by-frame 2D drawing over the shot (flipbook tracks).
    case flipbook
    /// Drag on the ground to scatter copies of the selection.
    case scatter
    /// Model ▸ Edit: pick faces, edges and corners, push/pull, sketch on surfaces (`ModelingState`).
    case model
    /// Paint ▸ Colour: colour painted on models with the brush engine (`ColourPaintSettings`).
    case paint
    /// Rig: bones drawn through an object, weights painted, the person rig's dots (`RigSettings`).
    case rig
    /// Animate ▸ Path (A1): the Pencil draws the way the selected thing goes.
    case animate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select: "Select"
        case .lasso: "Lasso"
        case .ink: "Ink"
        case .draw: "Solid shape"
        case .shadowBrush: "Shadow Brush"
        case .flipbook: "Flipbook"
        case .scatter: "Scatter"
        case .model: "Shape"
        case .paint: "Colour"
        case .rig: "Rig"
        case .animate: "Path"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .lasso: "lasso"
        case .ink: "pencil.tip"
        case .draw: "scribble.variable"
        case .shadowBrush: "circle.lefthalf.striped.horizontal"
        case .flipbook: "book.pages"
        case .scatter: "circle.hexagongrid"
        case .model: "cube.transparent"
        case .paint: "paintbrush.pointed"
        case .rig: "figure.walk.motion"
        case .animate: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// Tools where the Pencil (and, if allowed, a finger) paints instead of navigating.
    public var paints: Bool {
        self == .ink || self == .draw || self == .shadowBrush || self == .flipbook || self == .paint || self == .rig || self == .animate
    }

    /// The Draw tools (top right: Draw).
    public var draws: Bool { self == .ink || self == .draw || self == .flipbook }

    /// The Paint tools (top right: Paint): on objects and over the ground.
    public var paintsSurfaces: Bool { self == .shadowBrush || self == .scatter || self == .paint }

    /// Tools whose strokes take the colour in the hand (the sidebar shows its colour well for them). The Shadow
    /// Brush isn't one: it moves the Look's own shadow.
    public var putsColourDown: Bool { self == .ink || self == .draw || self == .flipbook || self == .paint }

    /// Tools whose strokes land on the sheet (CONTEXT §10.10): ink and solid shapes (flipbooks too, unless they are
    /// stuck to the camera; precise sketching through the Model tool's sketch mode).
    public var usesSheet: Bool { self == .ink || self == .draw || self == .flipbook }
}

/// The floating panels the corner clusters open. One at a time; tapping its button again closes it. Draw opens no panel
/// (its bar is under the stage, U5) and Animate calls the timeline (docs/LAYOUT.md).
public enum ClusterPanel: String, Identifiable, Sendable {
    // Top-left: document and app (the scene opens from its name, under the cluster).
    case actions, look, library, scene
    // Top-right: making.
    case model, rig

    public var id: String { rawValue }

    public var isLeading: Bool {
        switch self {
        case .actions, .look, .library, .scene: true
        default: false
        }
    }
}

/// The Model panel's pages: things to add, shaping (sketch, push/pull, booleans), snapping and measuring.
public enum ModelPage: String, CaseIterable, Identifiable, Sendable {
    case add, shape, precision

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .add: "Add"
        case .shape: "Edit"
        case .precision: "Precision"
        }
    }

    public var systemImage: String {
        switch self {
        case .add: "plus"
        case .shape: "cube.transparent"
        case .precision: "ruler"
        }
    }
}

/// The Library's pages (CONTEXT §10.11): Things (the Kit by set), Characters (make one, the ready-made ones, everything
/// with a skeleton), Motion, and Yours (what you imported, built and saved).
public enum LibraryPage: String, CaseIterable, Identifiable, Sendable {
    case things, characters, motion, yours

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .things: "Things"
        case .characters: "Characters"
        case .motion: "Motion"
        case .yours: "Yours"
        }
    }

    public var systemImage: String {
        switch self {
        case .things: "shippingbox"
        case .characters: "figure.stand"
        case .motion: "figure.run"
        case .yours: "person.crop.square"
        }
    }
}

/// Sheets over the editor (one at a time).
public enum EditorSheet: String, Identifiable, Sendable {
    case export, audio, transcript, scripts, bridge, blobBuilder, characterBuilder, settings, diagnostics, gestures, timelineSettings, learn
    /// A made character for games: engines, sprite sheets, turnaround (K1).
    case gameExport
    /// The brush library (and Brush Studio) for the drawing tool in `EditorModel.brushTool`.
    case brushes

    public var id: String { rawValue }
}

/// Solid shapes drawn on the sheet: what a stroke becomes, how wide, mirrored or not.
public struct DrawSettings: Equatable, Sendable {
    public var style: DrawingRecipe.Style = .tube
    /// Stroke width in metres at full pressure.
    public var width: Double = 0.05
    public var smoothing: Double = 0.5
    public var mirror = false
    public var extrudeDepth: Double = 0.3
    public var segments = 7

    public init() {}
}

/// What the Pencil does with ink: draw strokes, erase them, push them into a new shape (Draw's Smudge, U5), or pick
/// strokes with a loop (the quick menu's lasso while drawing).
public enum InkMode: String, CaseIterable, Identifiable, Sendable {
    case draw, erase, reshape, select

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .draw: "Draw"
        case .erase: "Erase"
        case .reshape: "Smudge"
        case .select: "Select strokes"
        }
    }

    public var systemImage: String {
        switch self {
        case .draw: "pencil.tip"
        case .erase: "eraser"
        case .reshape: "hand.point.up.left.and.text"
        case .select: "lasso"
        }
    }
}

/// Ink strokes: width at full pressure and opacity of new strokes, the eraser's size. (Smoothing is the brush's own and
/// the Pencil page's stabilisation, nothing more: U5.)
public struct InkSettings: Equatable, Sendable {
    public var mode: InkMode = .draw
    /// Half-width in metres at full pressure.
    public var width: Double = 0.006
    public var opacity: Double = 1
    /// Eraser radius in points.
    public var eraserRadius: Double = 14

    public init() {}
}

/// The Shadow Brush: how big, how strong, and which way.
public struct ShadowBrushSettings: Equatable, Sendable {
    /// Radius in metres.
    public var radius: Double = 0.15
    /// Bias per dab at full pressure (0…1).
    public var strength: Double = 0.35
    /// Push the shadow in (darker) or pull it out (lighter).
    public var pushesShadow = true

    public init() {}
}

public struct ScatterPanelSettings: Equatable, Sendable {
    public var count = 20
    public var scaleVariation = 0.25
    public var spacing = 0.8

    public init() {}
}

/// The timeline's two modes, shown as words (CONTEXT §10.10): Perform (record by moving things while time runs) and
/// Keys. Sliding a whole animation in time is dragging its bar, in either.
public enum TimelineMode: String, CaseIterable, Identifiable, Sendable {
    case perform, keyframe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .perform: "Perform"
        case .keyframe: "Keys"
        }
    }

    public var systemImage: String {
        switch self {
        case .perform: "record.circle"
        case .keyframe: "diamond"
        }
    }
}

public enum PerformPhase: Equatable, Sendable {
    case idle
    /// Armed (Procreate Dreams' Performing): "Ready" shows, and the first touch on the stage starts time.
    case ready
    /// A face, a voice or the iPad's motion performs without a touch: 3-2-1, then time runs.
    case countdown(Int)
    case recording

    /// Ready or recording: a touch on the stage performs.
    public var isArmed: Bool { self == .ready || self == .recording }
}

public struct PerformSettings: Equatable, Sendable {
    /// Motion filtering 0…1 (0 keeps every wobble).
    public var smoothing = 0.3
    /// How far a finger movement moves the performed object (1 = under the finger).
    public var sensitivity = 1.0
    /// Apple Pencil Pro barrel roll turns the object while it moves.
    public var barrelRoll = true

    public init() {}
}

/// One performed property of one object.
public struct PerformChannel: Hashable, Sendable {
    public var object: ObjectID
    public var property: PropertyKey
}

public enum StaggerChoice: String, CaseIterable, Identifiable, Sendable {
    case selection, leftToRight, rightToLeft, frontToBack, wave

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .selection: "Selection order"
        case .leftToRight: "Left → right"
        case .rightToLeft: "Right → left"
        case .frontToBack: "Front → back"
        case .wave: "Wave from centre"
        }
    }
}

public struct StaggerPanelSettings: Equatable, Sendable {
    public var delay = 0.08
    public var order: StaggerChoice = .leftToRight
    public var randomTiming = 0.0
    public var randomStrength = 0.0

    public init() {}
}

/// Ways to pick many keys at once.
public enum KeyQuery: String, CaseIterable, Identifiable, Sendable {
    case all, afterPlayhead, beforePlayhead, atPlayhead, loop, invert, none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All keys"
        case .afterPlayhead: "Everything after the playhead"
        case .beforePlayhead: "Everything before the playhead"
        case .atPlayhead: "Keys at the playhead"
        case .loop: "Keys in the loop"
        case .invert: "Invert selection"
        case .none: "Select none"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "checkmark.circle"
        case .afterPlayhead: "arrow.right.to.line"
        case .beforePlayhead: "arrow.left.to.line"
        case .atPlayhead: "line.3.horizontal"
        case .loop: "repeat"
        case .invert: "circle.lefthalf.filled"
        case .none: "xmark.circle"
        }
    }
}

/// Where a puppet joint's pivot goes.
public enum PivotPlace: String, CaseIterable, Sendable {
    case top, center, bottom

    public var title: String {
        switch self {
        case .top: "Joint at the top (arm, leg)"
        case .center: "Joint in the middle"
        case .bottom: "Joint at the bottom"
        }
    }
}

/// A picture or video in the shot: standing in the world, or flat over the frame.
public enum MediaPlacement: String, Sendable {
    case card
    case overlay
}

/// What the library is open for.
public enum LibraryPurpose: Equatable, Sendable {
    case place
    case swap(ObjectID)
}

/// Easing presets offered for selected keys.
/// How a move feels between two keys, in four words (a key's menu); the graph editor holds the rest.
public enum KeyFeel: String, CaseIterable, Identifiable, Sendable {
    case ease, snap, bounce, straight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ease: "Ease"
        case .snap: "Snap"
        case .bounce: "Bounce"
        case .straight: "Straight"
        }
    }

    public var systemImage: String {
        switch self {
        case .ease: "point.topleft.down.to.point.bottomright.curvepath"
        case .snap: "bolt"
        case .bounce: "arrow.up.and.down"
        case .straight: "line.diagonal"
        }
    }

    /// Ease in and out; a quick start that overshoots and settles; a bounce at the end; an even speed.
    public var easing: Easing {
        switch self {
        case .ease: .easeInOut
        case .snap: .backOut
        case .bounce: .bounce
        case .straight: .linear
        }
    }
}

public enum EasingChoice: String, CaseIterable, Identifiable, Sendable {
    case linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in & out"
        case .backOut: "Overshoot"
        case .bounce: "Bounce"
        case .elastic: "Elastic"
        case .step: "Step (hold)"
        }
    }

    public var easing: Easing {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn
        case .easeOut: .easeOut
        case .easeInOut: .easeInOut
        case .backOut: .backOut
        case .bounce: .bounce
        case .elastic: .elastic
        case .step: .step
        }
    }

    /// Bezier handles that approximate the preset (where a custom curve starts).
    public var bezier: (Double, Double, Double, Double) {
        switch self {
        case .linear, .step: (0.25, 0.25, 0.75, 0.75)
        case .easeIn: (0.55, 0, 1, 0.45)
        case .easeOut: (0, 0.55, 0.45, 1)
        case .easeInOut: (0.65, 0, 0.35, 1)
        case .backOut: (0.34, 1.56, 0.64, 1)
        case .bounce, .elastic: (0.2, 1.4, 0.4, 0.9)
        }
    }
}
