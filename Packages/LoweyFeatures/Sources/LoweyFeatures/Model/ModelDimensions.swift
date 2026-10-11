import HmmDesign
import LoweyCore
import SwiftUI

/// The numbers floating beside what the Model tool measures: the push/pull distance, the sides of the rectangle just
/// drawn, a circle's diameter, a line's length. Tap one and our number pad opens beside it (never the system keyboard,
/// CONTEXT §10.10) to type an exact length (`25`, `2×12`, `1.5 cm`).
struct ModelDimensions: View {
    let editor: EditorModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(editor.dimensionLabels) { label in
                DimensionChip(editor: editor, label: label)
                    .position(label.point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DimensionChip: View {
    let editor: EditorModel
    let label: DimensionLabel
    @Environment(\.hmmTheme) private var theme

    private var editing: Bool { editor.modeling.editing == label.field }

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            if !editor.dimensionTapped(label.field) { editor.modeling.editing = label.field }
        } label: {
            Text(label.text).monospacedDigit()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dimension-\(Self.identifier(label.field))")
        .accessibilityLabel(Text(label.text))
        .accessibilityHint(Self.hint(label.field))
        // The pad starts empty, the current size its placeholder: what is typed replaces it.
        .hmmNumberPad(isPresented: Binding(get: { editing }, set: { shown in
            if !shown, editing { editor.modeling.editing = nil }
        }), placeholder: label.text, units: LengthUnit.allCases.map(\.symbol)) { text in
            editor.submitDimension(label.field, text: text)
        }
        .font(.hmm(.footnote, weight: .semibold))
        .padding(.horizontal, HmmSpacing.s)
        .frame(minHeight: 32)
        .background(Capsule().fill(editing ? theme.surface : theme.accent))
        .foregroundStyle(editing ? theme.text : theme.onAccent)
        .contentShape(Capsule())
    }

    static func identifier(_ field: DimensionField) -> String {
        switch field {
        case .pull: "pull"
        case .rectangleSide(true): "width"
        case .rectangleSide(false): "depth"
        case .diameter: "diameter"
        case .lineLength: "length"
        case .offset: "offset"
        case .shapeAmount: "shape-size"
        case .measured: "measured"
        case let .kept(id): "kept-\(id.raw)"
        case .wallHeight: "wall-height"
        case .wallThickness: "wall-thickness"
        case .sketching: "sketch-readout"
        }
    }

    static func hint(_ field: DimensionField) -> Text {
        switch field {
        case .measured: Text("Keep this measurement on the stage")
        case .kept: Text("Select this dimension")
        default: Text("Type an exact length")
        }
    }
}
