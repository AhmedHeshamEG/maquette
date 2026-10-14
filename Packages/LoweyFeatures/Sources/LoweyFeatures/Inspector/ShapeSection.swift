import HmmDesign
import LoweyCore
import SwiftUI

/// The thing's shape, one step deeper in its panel (U6): its sides typed to a length, the Smooth switch (and making it
/// real), the smooth angle or flat shading, its triangles, clean topology, linked copies, the pivot, closing holes.
struct ShapeSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @State private var faces = 2000.0
    @State private var gesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            sizes
            if ModelingOperations.canModel(object) { smooth }
            shading
            cleanUp
            links
            pivot
        }
    }

    // MARK: Sizes

    private var sizes: some View {
        HStack(spacing: HmmSpacing.xxs) {
            ForEach(CoreAxis.allCases, id: \.self) { axis in
                if let length = editor.selectionLength(axis) {
                    HmmNumberPill(Self.side(axis), value: Binding(get: { length / editor.units.metres }, set: { value in
                        editor.setSelectionLength(axis, to: value * editor.units.metres, gesture: gesture)
                    }), scrub: HmmScrub(fine: 1, range: 0.001 ... 1_000_000), format: { editor.units.format($0 * editor.units.metres, symbol: false) },
                    parse: { text in editor.parseLength(text).map { $0 / editor.units.metres } }, onEditingChanged: { editing in
                        if !editing {
                            editor.endGesture()
                            gesture = UUID().uuidString
                        }
                    })
                    .accessibilityIdentifier("size-\(axis.rawValue)")
                }
            }
        }
    }

    static func side(_ axis: CoreAxis) -> String {
        switch axis {
        case .x: "Width"
        case .y: "Height"
        case .z: "Depth"
        }
    }

    // MARK: Smooth

    private var smooth: some View {
        let levels = editor.smoothLevels(of: object)
        return HStack(spacing: HmmSpacing.xs) {
            Text("Smooth").font(.hmm(.body))
            Spacer()
            Picker("Smooth", selection: Binding(get: { levels }, set: { editor.setSmooth($0) })) {
                Text("Off").tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .accessibilityIdentifier("smooth-levels")
            if levels > 0 {
                HmmButton("checkmark.seal", label: "Make the smoothing real", size: 36) { editor.applySmooth() }
                    .accessibilityIdentifier("smooth-apply")
            }
        }
    }

    // MARK: Shading

    private var shading: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Toggle("Flat shading", isOn: Binding(get: { object.shading == .flat }, set: { editor.setFlatShading($0) }))
                .font(.hmm(.body))
                .accessibilityIdentifier("flat-shading")
            if object.shading != .flat {
                LabeledSlider(title: "Smooth angle", value: object[.smoothAngle]?.floatValue ?? 0, range: 0 ... 180,
                              format: { $0 < 0.5 ? String(localized: "Every edge crisp") : "\(Int($0.rounded()))°" }) { value in
                    editor.setSmoothAngle(value < 0.5 ? nil : value, gesture: gesture)
                } done: {
                    editor.endGesture()
                    gesture = UUID().uuidString
                }
                .accessibilityIdentifier("smooth-angle")
            }
            if let count = editor.triangleCount(of: object) {
                HStack {
                    Text("Triangles").foregroundStyle(theme.text2)
                    Spacer()
                    Text(count.formatted()).monospacedDigit()
                        .accessibilityIdentifier("triangle-count")
                }
                .font(.hmm(.body))
            }
        }
    }

    // MARK: Clean topology

    private var cleanUp: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HStack(spacing: HmmSpacing.xs) {
                HmmNumberPill("Faces", value: $faces, scrub: HmmScrub(fine: 10, range: 50 ... 50000), format: { "\(Int($0.rounded()))" })
                    .accessibilityIdentifier("clean-faces")
                if editor.modeling.cleaning == object.id {
                    Text("Cleaning up…").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                } else {
                    HmmPillButton("Clean up the shape", systemName: "square.grid.4x3.fill") { editor.cleanUpShape(faces: Int(faces)) }
                        .accessibilityIdentifier("clean-up")
                }
            }
            Hint("Turns it into even four-sided faces, the kind games and rigs like. The shape stays.")
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Close holes", systemName: "circle.dashed.inset.filled") { editor.fillHolesOfSelection() }
                    .accessibilityIdentifier("fill-holes")
                HmmPillButton("Join close corners", systemName: "arrow.down.right.and.arrow.up.left") { editor.mergeByDistance() }
                    .accessibilityIdentifier("merge-distance")
            }
        }
        .onAppear { faces = Double(editor.shownSurface(of: object).map { QuadRemesh.suggestedFaces(for: $0) } ?? 2000) }
    }

    // MARK: Links and the pivot

    private var links: some View {
        HStack(spacing: HmmSpacing.xs) {
            HmmPillButton("Linked copy", systemName: "link") { editor.makeLinkedCopy() }
                .accessibilityIdentifier("linked-copy")
            if editor.isLinked(object) {
                HmmPillButton("Unlink", systemName: "link.badge.plus") { editor.unlinkSelection() }
                    .accessibilityIdentifier("unlink")
            }
        }
    }

    private var pivot: some View {
        HStack(spacing: HmmSpacing.xs) {
            Text("Pivot").font(.hmm(.body))
            Spacer()
            ChoiceChip(title: "Middle", systemName: "circle.circle", isOn: false) { editor.movePivot(to: .middle) }
                .accessibilityIdentifier("pivot-middle")
            ChoiceChip(title: "Base", systemName: "circle.bottomhalf.filled", isOn: false) { editor.movePivot(to: .base) }
                .accessibilityIdentifier("pivot-base")
        }
    }
}
