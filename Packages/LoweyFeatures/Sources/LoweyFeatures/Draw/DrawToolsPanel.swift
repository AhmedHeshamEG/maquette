import HmmDesign
import LoweyCore
import SwiftUI

/// Draw: everything the Pencil draws (CONTEXT §10.10), all on the sheet: ink, solid shapes, precise sketching and
/// flipbooks. A finger-tap places the sheet; its grip and shapes are on its edge. Pencil or hand is automatic.
struct DrawToolsPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel("Draw", width: 360, sizing: HmmPanelSizing(id: "draw"), close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                HStack(spacing: HmmSpacing.xs) {
                    ChoiceChip(title: "Ink", systemName: "pencil.tip", isOn: editor.tool == .ink) { editor.tool = .ink }
                        .accessibilityIdentifier("tool-ink")
                    ChoiceChip(title: "Solid shape", systemName: "scribble.variable", isOn: editor.tool == .draw) { editor.tool = .draw }
                        .accessibilityIdentifier("tool-draw")
                    ChoiceChip(title: "Sketch", systemName: "pencil.and.ruler", isOn: editor.isSketching) { editor.startSketching(.line) }
                        .accessibilityIdentifier("tool-sketch")
                    ChoiceChip(title: "Flipbook", systemName: "book.pages", isOn: editor.tool == .flipbook) { editor.tool = .flipbook }
                        .accessibilityIdentifier("tool-flipbook")
                }
                switch editor.tool {
                case .draw: solidShape
                case .flipbook: FlipbookSection(editor: editor)
                case .model where editor.isSketching: SketchSection(editor: editor)
                default: InkSection(editor: editor)
                }
                if editor.drawsOnSheet {
                    Hint("Tap with a finger to move the sheet there: onto a surface, or into the air facing you. Drag its grip to push it nearer or farther.")
                }
            }
        }
        .onAppear { if !editor.tool.draws, !editor.isSketching { editor.tool = .ink } }
    }

    private var solidShape: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            PanelSection("Becomes") {
                TileGrid(minimum: 74) {
                    ForEach(DrawingRecipe.Style.solid, id: \.self) { style in
                        TileButton(title: style.title, systemName: style.systemImage) { editor.draw.style = style }
                            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card).stroke(Color.accentColor, lineWidth: editor.draw.style == style ? 2 : 0))
                    }
                }
                Hint(editor.draw.style.hint)
            }
            if editor.draw.style == .extrude {
                LabeledSlider(title: "Depth", value: editor.draw.extrudeDepth, range: 0.02 ... 3) { editor.draw.extrudeDepth = $0 }
            }
            Toggle("Mirror", isOn: $editor.draw.mirror)
            Hint("Width and smoothing are the sidebar's sliders. Draw, then hold: the stroke snaps to a clean line, circle or rectangle.")
        }
        .font(.hmm(.body))
    }
}

/// Draw ▸ Sketch: precise shapes on the sheet (moved here from Model ▸ Edit). Draw with the Pencil, or tap the corners;
/// the length and angle float beside the tip, round angles and lines already drawn snap with a named ghost line, and
/// every size is a number to tap and type.
struct SketchSection: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            PanelSection("Shapes") {
                TileGrid {
                    ForEach(SketchKind.allCases) { kind in
                        TileButton(title: kind.title, systemName: kind.systemImage, identifier: "sketch-\(kind.rawValue)") {
                            editor.startSketching(kind)
                            editor.openPanel = nil
                        }
                        .overlay(RoundedRectangle(cornerRadius: HmmRadius.card)
                            .stroke(Color.accentColor, lineWidth: editor.modeling.mode == .sketch(kind) ? 2 : 0))
                    }
                }
            }
            Hint("Draw on the sheet with the Pencil, or tap the corners. Its length and angle show as you go; tap a number to type it.")
            Hint("Closed shapes fill: pull one up into a solid with Model ▸ Edit.")
        }
        .font(.hmm(.body))
    }
}

/// The sketch's bar under the stage: the shapes, Done for a line or curve still open, and leaving.
struct SketchOptionsBar: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(SketchKind.allCases) { kind in
                HmmButton(kind.systemImage, label: kind.title, isOn: editor.modeling.mode == .sketch(kind), size: 36) {
                    editor.startSketching(kind)
                }
            }
            if editor.modeling.pending != nil {
                HmmButton("checkmark", label: "Done", size: 36) { editor.finishSketchShape() }
            }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.stopModeling() }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}

/// The solid-shape tool's quick options at the bottom of the stage.
struct DrawOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(DrawingRecipe.Style.solid, id: \.self) { style in
                ChoiceChip(title: style.title, systemName: style.systemImage, isOn: editor.draw.style == style) { editor.draw.style = style }
            }
            HmmButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror", isOn: editor.draw.mirror, size: 36) {
                editor.draw.mirror.toggle()
            }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
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
