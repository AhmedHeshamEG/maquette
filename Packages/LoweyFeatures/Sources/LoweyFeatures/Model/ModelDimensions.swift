import HmmDesign
import LoweyCore
import SwiftUI

/// The numbers floating beside what the Model tool measures: the push/pull distance, the sides of the rectangle just
/// drawn, a circle's diameter, a line's length. Each is a 44 pt pill (U5): drag it to change it (slowly for fine, fast
/// for coarse), tap it and our number pad opens beside it (never the system keyboard, CONTEXT §10.10) to type an exact
/// length (`25`, `2×12`, `1.5 cm`).
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
    @State private var scrub: (start: Double, last: CGSize, gesture: String)?
    @Environment(\.hmmTheme) private var theme

    /// Every number is a slider: dragged, the size changes with the hand (U5).
    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard let current = editor.dimensionValue(label.field), editor.canScrub(label.field) else { return }
                let state = scrub ?? (current, .zero, UUID().uuidString)
                let delta = HmmScrub.delta(dx: value.translation.width - state.last.width, dy: value.translation.height - state.last.height)
                let speed = HmmScrub.delta(dx: value.velocity.width, dy: value.velocity.height)
                let next = HmmScrub(fine: max(current * 0.004, 0.0005), range: 0.0005 ... 10000).value(from: current, delta: delta, speed: speed)
                scrub = (state.start, value.translation, state.gesture)
                editor.scrubDimension(label.field, to: next, gesture: state.gesture)
            }
            .onEnded { _ in
                scrub = nil
                editor.endGesture()
                HmmHaptics.play(.commit)
            }
    }

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
        .simultaneousGesture(drag)
        .font(.hmmNumbers(.body, weight: .semibold))
        .padding(.horizontal, HmmSpacing.s)
        .frame(minWidth: HmmTarget.minimum, minHeight: HmmTarget.minimum)
        .background(Capsule().fill(editing ? theme.surface : theme.accent))
        .foregroundStyle(editing ? theme.text : theme.onAccent)
        .contentShape(Capsule())
        .overlay(alignment: .trailing) {
            if Self.locks(label.field) { lock.offset(x: 40) }
        }
    }

    /// A size of the shape just drawn can be locked (U6): its sketch keeps it while another changes.
    private var lock: some View {
        let locked = editor.isLocked(label.field)
        return Button {
            HmmHaptics.play(.selection)
            editor.toggleLock(label.field)
        } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(locked ? theme.accent : theme.text2)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? Text("Unlock this size") : Text("Lock this size"))
        .accessibilityIdentifier("lock-\(Self.identifier(label.field))")
    }

    static func locks(_ field: DimensionField) -> Bool {
        switch field {
        case .rectangleSide, .diameter, .lineLength: true
        default: false
        }
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
