import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Precision: the grid on the ground, the units sizes are shown and typed in, the measure tool, kept dimensions
/// and the section view. What snaps is the Snap magnet's, on the stage (CONTEXT §10.10): tap it on or off, hold it for
/// the details.
struct PrecisionPage: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Grid and units") { snapping }
            PanelSection("Measure") { measuring }
            PanelSection("Section view") { section }
        }
        .font(.hmm(.body))
    }

    private var snapping: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Grid on the ground", isOn: $editor.showsGrid)
                .accessibilityIdentifier("show-grid")
            Picker("Units", selection: $editor.units) {
                ForEach(LengthUnit.allCases, id: \.self) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("units")
            Hint("This project remembers these. What snaps: hold the magnet on the stage.")
        }
    }

    private var measuring: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmPillButton("Measure", systemName: "ruler") {
                editor.startModeling(.measure)
                editor.openPanel = nil
            }
            .accessibilityIdentifier("measure")
            Toggle("Show kept dimensions", isOn: $editor.precision.showsDimensions)
                .accessibilityIdentifier("show-dimensions")
            Hint("Tap two points: corners and edges snap. Tap the number to keep it on the stage; it moves with what it measures.")
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                ChoiceChip(title: "Off", systemName: "circle.slash", isOn: editor.precision.section == nil) { editor.setSection(nil) }
                    .accessibilityIdentifier("section-off")
                ForEach(SymmetryAxis.allCases, id: \.self) { axis in
                    ChoiceChip(title: axis.rawValue.uppercased(), systemName: Self.icon(for: axis), isOn: isCut(along: axis)) {
                        editor.setSection(axis)
                    }
                    .accessibilityIdentifier("section-\(axis.rawValue)")
                }
            }
            if editor.pickedFace != nil {
                HmmPillButton("Cut along the picked face", systemName: "square.split.diagonal") { editor.sectionAlongPickedFace() }
            }
            if editor.precision.section != nil {
                LabeledSlider(title: "Where it cuts", value: editor.sectionPosition, range: -1 ... 1, format: { _ in "" }) { editor.sectionPosition = $0 }
                HmmPillButton("Keep the other side", systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") { editor.flipSection() }
            }
            Hint("Cuts the stage open to show inside a part, a wall or a room. Exports are never cut.")
        }
    }

    private func isCut(along axis: SymmetryAxis) -> Bool {
        guard let normal = editor.precision.section?.normal else { return false }
        return abs(normal.dot(axis.normal)) > 0.999
    }

    static func icon(for axis: SymmetryAxis) -> String {
        switch axis {
        case .x: "square.split.2x1"
        case .y: "square.split.1x2"
        case .z: "rectangle.split.2x1"
        }
    }

    /// Grid sizes that read well in each unit.
    static func gridSizes(for unit: LengthUnit) -> [Double] {
        switch unit {
        case .millimetre: [0.001, 0.005, 0.01, 0.05, 0.1]
        case .centimetre: [0.01, 0.1, 0.25, 0.5, 1]
        case .metre: [0.1, 0.25, 0.5, 1, 5]
        case .inch: [0.0254 / 8, 0.0254 / 4, 0.0254, 0.0254 * 6, 0.3048]
        case .foot: [0.0254, 0.0254 * 6, 0.3048, 0.3048 * 2, 0.3048 * 10]
        }
    }
}
