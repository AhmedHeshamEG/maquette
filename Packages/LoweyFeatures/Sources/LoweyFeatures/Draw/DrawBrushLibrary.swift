import HmmDesign
import LoweyCore
import SwiftUI

/// Draw's brush library, dropped down from the Brush (CONTEXT §10.10 and §10.11): sets on the left, the set's brushes
/// on the right, the canvas still visible. The library's own sets draw lines (a painting set puts colour on models);
/// under them, the sets that make things: Solids, Shapes, Shadow. The whole library (Brush Studio, new sets, imports)
/// is the last row.
struct DrawBrushLibrary: View {
    @Bindable var editor: EditorModel
    let close: () -> Void
    @State private var chosen: String?
    @Environment(\.hmmTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var brushes: BrushModel { editor.app.brushes }
    private var ink: RGBA { colorScheme == .dark ? RGBA(0.93, 0.93, 0.94) : RGBA(0.11, 0.11, 0.12) }

    /// The set shown on the right: the one tapped, else the one holding what's in the hand.
    private var shown: String {
        if let chosen { return chosen }
        if let making = DrawMakingSet.allCases.first(where: { $0.contains(editor.drawBrush) }) { return making.rawValue }
        let current = brushes.brush(for: .ink).id
        return brushes.library.sets.first { $0.brushes.contains(current) }?.id ?? brushes.library.sets.first?.id ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(brushes.library.sets) { set in setRow(id: set.id, label: Text(verbatim: set.name)) }
                        Divider().padding(.vertical, HmmSpacing.xxs)
                        ForEach(DrawMakingSet.allCases) { set in setRow(id: set.rawValue, label: Text(LocalizedStringKey(set.title))) }
                    }
                    .padding(HmmSpacing.xs)
                }
                .frame(width: 150)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) { rightColumn }
                        .padding(HmmSpacing.xs)
                }
                .frame(width: 270)
            }
            .frame(height: 360)
            Divider()
            Button {
                close()
                editor.brushTool = .ink
                editor.sheet = .brushes
            } label: {
                Label("The whole library: Brush Studio, new sets, imports", systemImage: "square.grid.2x2")
                    .font(.hmm(.footnote, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brush-library-open")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brush-dropdown")
    }

    private func setRow(id: String, label: Text) -> some View {
        Button {
            HmmHaptics.play(.selection)
            chosen = id
        } label: {
            label
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(id == shown ? theme.onAccent : theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .padding(.horizontal, HmmSpacing.xs)
                .background(id == shown ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: HmmRadius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brush-set-\(id)")
    }

    @ViewBuilder private var rightColumn: some View {
        if let making = DrawMakingSet(rawValue: shown) {
            ForEach(making.kinds.indices, id: \.self) { index in kindRow(making.kinds[index]) }
            makingOptions(making)
        } else if let set = brushes.library.sets.first(where: { $0.id == shown }) {
            ForEach(set.brushes, id: \.self) { id in
                if let brush = brushes.library.brush(id) { brushRow(brush, paints: set.paintsSurfaces) }
            }
            if set.paintsSurfaces { Hint("These put colour on a model. Started in the air, they draw a line.") }
        }
    }

    private func brushRow(_ brush: Brush, paints: Bool) -> some View {
        let chosen = editor.drawBrush.isLibraryBrush && brushes.brush(for: .ink).id == brush.id
        return Button {
            HmmHaptics.play(.selection)
            brushes.select(brush.id, for: .ink)
            editor.chooseDrawBrush(paints ? .paint : .lines)
            close()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                BrushPreviewImage(brushes: brushes, brush: brush, width: 240, height: 36, color: ink)
                Text(brush.name).font(.hmm(.caption)).foregroundStyle(chosen ? theme.accent : theme.text2).lineLimit(1)
            }
            .padding(HmmSpacing.xxs)
            .background(chosen ? theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: HmmRadius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(brush.name))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func kindRow(_ kind: DrawBrushKind) -> some View {
        let chosen = editor.drawBrush == kind
        return Button {
            HmmHaptics.play(.selection)
            editor.chooseDrawBrush(kind)
            close()
        } label: {
            Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage)
                .font(.hmm(.body, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? theme.accent : theme.text)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, HmmSpacing.xs)
                .background(chosen ? theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: HmmRadius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("draw-kind-\(kind.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    /// What a making set can change, under its brushes.
    @ViewBuilder private func makingOptions(_ set: DrawMakingSet) -> some View {
        switch set {
        case .solids:
            Toggle("Mirror", isOn: $editor.draw.mirror).font(.hmm(.body)).padding(.top, HmmSpacing.xs)
            if editor.draw.style == .extrude {
                LabeledSlider(title: "Depth", value: editor.draw.extrudeDepth, range: 0.02 ... 3) { editor.draw.extrudeDepth = $0 }
            }
            Hint(editor.draw.style.hint)
        case .shapes:
            Hint("Drag from corner to corner, from the middle out, or from point to point. Hold at the end of any line for a clean one.")
        case .shadow:
            PanelSection("Presets on the selection") {
                FlowChips(items: ShadowPreset.allCases.map { ($0.rawValue, $0.title) }, isOn: { _ in false }) { key in
                    if let preset = ShadowPreset(rawValue: key) { editor.applyShadowPreset(preset) }
                }
            }
            if editor.selectionHasShadowPaint {
                HmmPillButton("Clear the shadow painting", systemName: "eraser", role: .destructive) { editor.clearShadowPaint() }
            }
        }
    }
}
