import HmmDesign
import LoweyCore
import SwiftUI

/// The brush a drawing or painting tool holds, drawing its sample stroke; tap and the brush library drops down from it
/// (CONTEXT §10.10: sets on the left, brushes on the right, the canvas still visible).
struct BrushRow: View {
    @Bindable var editor: EditorModel
    let tool: BrushTool
    @State private var dropped = false
    @Environment(\.hmmTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let brush = editor.currentBrush(for: tool)
        Button {
            editor.brushTool = tool
            dropped = true
        } label: {
            HStack(spacing: HmmSpacing.s) {
                BrushPreviewImage(brushes: editor.app.brushes, brush: brush, width: 120, height: 36,
                                  color: colorScheme == .dark ? RGBA(0.93, 0.93, 0.94) : RGBA(0.11, 0.11, 0.12))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Brush").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                    Text(brush.name).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").foregroundStyle(theme.text3)
            }
            .padding(HmmSpacing.xs)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Brush: \(brush.name)")
        .accessibilityIdentifier("brush-\(tool.rawValue)")
        .popover(isPresented: $dropped, arrowEdge: .bottom) {
            BrushDropDown(editor: editor, tool: tool) { dropped = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The brush library dropped down from the brush button: the sets on the left, the chosen set's brushes on the right.
/// Tap a brush to draw with it; the whole library (Brush Studio, new sets, imports) is one row further.
struct BrushDropDown: View {
    @Bindable var editor: EditorModel
    let tool: BrushTool
    let close: () -> Void
    @State private var chosenSet: String?
    @Environment(\.hmmTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var brushes: BrushModel { editor.app.brushes }
    private var ink: RGBA { colorScheme == .dark ? RGBA(0.93, 0.93, 0.94) : RGBA(0.11, 0.11, 0.12) }

    /// The set shown on the right: the one tapped, else the one holding the brush in the hand.
    private var set: BrushSet? {
        let sets = brushes.library.sets
        if let chosenSet, let set = sets.first(where: { $0.id == chosenSet }) { return set }
        let current = brushes.brush(for: tool).id
        return sets.first { $0.brushes.contains(current) } ?? sets.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(brushes.library.sets) { item in
                            Button {
                                HmmHaptics.play(.selection)
                                chosenSet = item.id
                            } label: {
                                Text(item.name)
                                    .font(.hmm(.footnote, weight: .semibold))
                                    .foregroundStyle(item.id == set?.id ? theme.onAccent : theme.text)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                    .padding(.horizontal, HmmSpacing.xs)
                                    .background(item.id == set?.id ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: HmmRadius.control))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(HmmSpacing.xs)
                }
                .frame(width: 150)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(set?.brushes ?? [], id: \.self) { id in
                            if let brush = brushes.library.brush(id) { row(brush) }
                        }
                    }
                    .padding(HmmSpacing.xs)
                }
                .frame(width: 270)
            }
            .frame(height: 340)
            Divider()
            Button {
                close()
                editor.brushTool = tool
                editor.sheet = .brushes
            } label: {
                Label("The whole library: Brush Studio, new sets, imports", systemImage: "square.grid.2x2")
                    .font(.hmm(.footnote, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brush-library-open")
        }
        .accessibilityIdentifier("brush-dropdown")
    }

    private func row(_ brush: Brush) -> some View {
        let chosen = brushes.brush(for: tool).id == brush.id
        return Button {
            HmmHaptics.play(.selection)
            brushes.select(brush.id, for: tool)
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
}

/// A brush drawing its sample stroke (drawn by the brush engine, cached by the brush model).
struct BrushPreviewImage: View {
    let brushes: BrushModel
    let brush: Brush
    let width: Double
    let height: Double
    let color: RGBA
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Reading the revision redraws the picture when a brush changes.
        let revision = brushes.revision
        Group {
            if revision >= 0, let image = brushes.preview(brush, width: width, height: height, color: color, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
