import HmmDesign
import LoweyCore
import SwiftUI

/// A tapped stroke's chip (U5: strokes stay editable): the brush and the colour in the hand, its thickness as a number
/// to drag or type, smooth, delete. It floats above the picked strokes; dragging along them with the Pencil reshapes
/// them.
struct StrokeChip: View {
    @Bindable var editor: EditorModel
    @State private var thickness = 100.0
    @State private var gesture = UUID().uuidString

    var body: some View {
        GeometryReader { geometry in
            if let rect = editor.pickedStrokesRect {
                chip
                    .fixedSize()
                    .position(x: min(max(rect.midX, 170), geometry.size.width - 170), y: max(rect.minY - 40, 90))
            }
        }
        .onChange(of: editor.inkStrokes) { _, _ in thickness = 100 }
    }

    private var chip: some View {
        HStack(spacing: HmmSpacing.xxs) {
            HmmButton("paintbrush.pointed", label: "The brush in the hand") { editor.restyleInkStrokes() }
            HmmButton("paintpalette", label: "The colour in the hand") { editor.recolourInk() }
            HmmNumberPill("Thickness", value: Binding(get: { thickness }, set: { value in
                let factor = value / max(thickness, 1)
                thickness = value
                if abs(factor - 1) > 1e-6 { editor.scaleInkStrokes(by: factor, gesture: gesture) }
            }), scrub: HmmScrub(fine: 1, range: 10 ... 800), format: { "\(Int($0.rounded())) %" }, onEditingChanged: { editing in
                if !editing {
                    editor.endGesture()
                    gesture = UUID().uuidString
                }
            })
            HmmButton("wand.and.rays", label: "Smooth") { editor.smoothInkStrokes() }
            HmmButton("trash", label: "Delete strokes", role: .destructive) { editor.deleteInkStrokes() }
            HmmButton("xmark", label: "Done") { editor.inkStrokes = [] }
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stroke-chip")
    }
}
