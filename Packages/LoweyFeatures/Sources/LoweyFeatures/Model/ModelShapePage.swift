import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Edit: sketch on any surface, pick faces / edges / corners to push and pull, and get a part ready to print.
/// (Combine, mirror and Make editable are on the selection, in its panel.) Choosing a sketch shape or a pick mode closes the panel so the stage is
/// free; the bar at the bottom holds what the pick can do (bevel, round, inset, shell).
struct ModelShapePage: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Sketch") {
                TileGrid {
                    ForEach(SketchKind.allCases) { kind in
                        TileButton(title: kind.title, systemName: kind.systemImage, identifier: "sketch-\(kind.rawValue)") {
                            start(.sketch(kind))
                        }
                    }
                }
                Hint("Tap on a face or the ground. Closed shapes fill; tap one and drag it up into a solid, or into a face to cut.")
            }
            PanelSection("Push & pull") {
                TileGrid {
                    ForEach(MeshSelection.Mode.allCases.reversed(), id: \.self) { mode in
                        TileButton(title: mode.label, systemName: Self.icon(for: mode), identifier: "pick-\(mode.rawValue)") {
                            start(.pick(mode))
                        }
                    }
                }
                Hint("Tap a face and drag it. Tap the number to type an exact size, like 25 or 2*12.")
            }
            PanelSection("3D print") {
                PrintCheckControls(editor: editor)
            }
        }
    }

    private func start(_ mode: ModelingMode) {
        editor.startModeling(mode)
        editor.openPanel = nil
    }

    static func icon(for mode: MeshSelection.Mode) -> String {
        switch mode {
        case .face: "square.fill"
        case .edge: "line.diagonal"
        case .vertex: "smallcircle.filled.circle"
        }
    }
}
