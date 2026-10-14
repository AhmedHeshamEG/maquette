import HmmDesign
import LoweyCore
import SwiftUI

/// Draw's bar under the stage (U5, CONTEXT §10.11): Procreate's five, Brush · Smudge · Erase · Sheets · Colour. Tap the
/// Brush while it's in the hand and the library drops down; Sheets becomes Layers while a paint brush is over a thing.
/// While a shape waits for more points, Done; while a picture is placed to project onto a model, Project and put it
/// away. No panel opens while drawing.
struct DrawBar: View {
    @Bindable var editor: EditorModel
    @State private var library = false
    @State private var sheets = false
    @State private var layers = false

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            if editor.colourPaint.picture != nil {
                picture
            } else {
                verbs
            }
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("draw-bar")
    }

    @ViewBuilder private var verbs: some View {
        let inUse = editor.drawVerbInUse
        HmmButton(editor.drawBrush.systemImage, label: "Brush", isOn: inUse == .brush, accent: inUse == .brush) {
            if inUse == .brush { library = true } else { editor.chooseDrawVerb(.brush) }
        }
        .accessibilityIdentifier("draw-brush")
        .popover(isPresented: $library, arrowEdge: .bottom) {
            DrawBrushLibrary(editor: editor) { library = false }
                .presentationCompactAdaptation(.popover)
        }
        HmmButton(DrawVerb.smudge.systemImage, label: "Smudge", isOn: inUse == .smudge, accent: inUse == .smudge) { editor.chooseDrawVerb(.smudge) }
            .accessibilityIdentifier("draw-smudge")
        HmmButton(DrawVerb.erase.systemImage, label: "Erase", isOn: inUse == .erase, accent: inUse == .erase) { editor.chooseDrawVerb(.erase) }
            .accessibilityIdentifier("draw-erase")
        if editor.drawShowsLayers {
            HmmButton("square.3.layers.3d", label: "Layers", isOn: layers) { layers = true }
                .accessibilityIdentifier("draw-layers")
                .popover(isPresented: $layers, arrowEdge: .bottom) {
                    LayersPopover(editor: editor)
                        .presentationCompactAdaptation(.popover)
                }
        } else {
            HmmButton("square.on.square", label: "Sheets", isOn: sheets) { sheets = true }
                .accessibilityIdentifier("draw-sheets")
                .popover(isPresented: $sheets, arrowEdge: .bottom) {
                    SheetsPopover(editor: editor)
                        .presentationCompactAdaptation(.popover)
                }
        }
        HmmColourWell(editor.paintColor.color) { editor.hands.choosingColour = true }
            .popover(isPresented: $editor.hands.choosingColour, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: HmmSpacing.s) {
                    HmmSectionHeader("Colour")
                    ColourChooser(editor: editor)
                }
                .padding(HmmSpacing.m)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("colour-chooser")
            }
        if editor.isSketching, editor.modeling.pending != nil {
            HmmButton("checkmark", label: "Done") { editor.finishSketchShape() }
                .accessibilityIdentifier("draw-done")
        }
    }

    /// A picture being placed to project onto a model.
    @ViewBuilder private var picture: some View {
        if editor.paintTarget?.paint != nil {
            HmmPillButton("Project", systemName: "light.beacon.max") { editor.projectPicture() }
                .accessibilityIdentifier("paint-project")
        }
        HmmButton("xmark", label: "Put the picture away") { editor.colourPaint.picture = nil }
    }
}
