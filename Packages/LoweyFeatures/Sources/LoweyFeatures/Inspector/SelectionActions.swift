import HmmDesign
import LoweyCore
import SwiftUI

/// What needs a selection lives on the selection (CONTEXT §10.10), and only shows when the selection can do it:
/// Combine for two or more shapes, Mirror and symmetry and Make editable for a shape, Scatter for anything.
struct SelectionActions: View {
    let editor: EditorModel

    var body: some View {
        let shapes = editor.modelableSelection
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            if shapes.count >= 2 {
                PanelSection("Combine") {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(MeshBoolean.Operation.allCases, id: \.self) { operation in
                            HmmPillButton(operation.label, systemName: Self.icon(for: operation)) { editor.combineSelection(operation) }
                                .accessibilityIdentifier("boolean-\(operation.rawValue)")
                        }
                    }
                    Hint("The first one picked keeps its look and place.")
                }
            }
            if !shapes.isEmpty || editor.modeling.target != nil { MirrorControls(editor: editor) }
            HStack(spacing: HmmSpacing.xs) {
                if editor.convertibleSelection != nil {
                    HmmPillButton("Make editable", systemName: "cube.transparent") { editor.makeSelectionEditable() }
                        .accessibilityIdentifier("make-editable")
                }
                HmmPillButton("Scatter copies", systemName: "circle.hexagongrid") {
                    editor.tool = .scatter
                    editor.foldInspector(true)
                }
                .accessibilityIdentifier("tool-scatter")
            }
        }
    }

    static func icon(for operation: MeshBoolean.Operation) -> String {
        switch operation {
        case .union: "square.on.square"
        case .subtract: "square.on.square.dashed"
        case .intersect: "square.on.square.intersection.dashed"
        }
    }
}

/// Mirror and symmetry, on the selected shape.
struct MirrorControls: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                Menu {
                    if editor.pickedFace != nil {
                        Button("Across the picked face") { editor.mirrorSelection(nil) }
                    }
                    Button("Across the middle, left to right") { editor.mirrorSelection(.x) }
                    Button("Across the middle, front to back") { editor.mirrorSelection(.z) }
                    Button("Across the ground") { editor.mirrorSelection(.y) }
                } label: {
                    Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .accessibilityIdentifier("mirror")
                Menu {
                    Button("Off") { editor.setSymmetry(nil) }
                    Button("Left and right") { editor.setSymmetry(.x) }
                    Button("Front and back") { editor.setSymmetry(.z) }
                    Button("Top and bottom") { editor.setSymmetry(.y) }
                } label: {
                    Label { symmetryTitle } icon: { Image(systemName: "square.split.2x1") }
                }
                .accessibilityIdentifier("symmetry")
            }
            Hint("Symmetry keeps both sides alike as you model: whatever you change on one side, the other follows.")
        }
    }

    private var symmetryTitle: Text {
        switch editor.selectionSymmetry {
        case .x: Text("Symmetry: left and right")
        case .y: Text("Symmetry: top and bottom")
        case .z: Text("Symmetry: front and back")
        case nil: Text("Symmetry")
        }
    }
}
