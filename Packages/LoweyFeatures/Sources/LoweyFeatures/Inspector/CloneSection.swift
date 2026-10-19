import HmmDesign
import LoweyCore
import SwiftUI

/// A thing's clones (D1): the layout and its numbers, then the effects, each with the field it acts through. The panel
/// shows only what the chosen layout and effect use.
struct CloneSection: View {
    let editor: EditorModel
    let object: SceneObject
    let clones: ObjectClones
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Layout", selection: Binding(get: { clones.layout.title }, set: { setLayout($0) })) {
                ForEach(["Grid", "Circle", "Line", "Along a path"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("clone-layout")
            layoutNumbers
            Text("\(clones.count) copies").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            ForEach(Array(clones.effects.enumerated()), id: \.element.id) { index, effect in
                CloneEffectRow(editor: editor, object: object, effect: effect, index: index)
            }
            Menu {
                ForEach(CloneEffect.Kind.allCases) { kind in
                    Button(LocalizedStringKey(kind.title)) { editor.addCloneEffect(kind, to: object.id) }
                }
            } label: {
                Label("Add an effect", systemImage: "plus.circle").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("clone-add-effect")
            if !clones.effects.isEmpty {
                LabeledSlider(title: "Effect strength", value: object[.effectStrength]?.floatValue ?? 1, range: 0 ... 2, format: NumberFormat.percent) {
                    editor.perform(.setProperties([PropertyChange(object: object.id, key: .effectStrength, value: .float($0))]), coalesceKey: "effect-strength")
                }
                Hint("Key it, or link it to the music, for a ripple on the beat.")
            }
            HmmPillButton("Remove clones", systemName: "xmark.bin", role: .destructive) { editor.removeClones(of: object.id) }
                .accessibilityIdentifier("clone-remove")
        }
    }

    @ViewBuilder private var layoutNumbers: some View {
        switch clones.layout {
        case let .grid(columns, rows, layers, spacing):
            Stepper("Across \(columns)", value: count(columns) { .grid(columns: $0, rows: rows, layers: layers, spacing: spacing) }, in: 1 ... 10)
            Stepper("Deep \(rows)", value: count(rows) { .grid(columns: columns, rows: $0, layers: layers, spacing: spacing) }, in: 1 ... 10)
            Stepper("High \(layers)", value: count(layers) { .grid(columns: columns, rows: rows, layers: $0, spacing: spacing) }, in: 1 ... 10)
            spacingSlider(spacing.x) { .grid(columns: columns, rows: rows, layers: layers, spacing: Vec3($0, $0, $0)) }
        case let .circle(count, radius, facesOut):
            Stepper("Copies \(count)", value: self.count(count) { .circle(count: $0, radius: radius, facesOut: facesOut) }, in: 2 ... 120)
            LabeledSlider(title: "Radius", value: radius, range: 0.1 ... 20, format: { NumberFormat.short($0) + " m" }) { value in
                set(.circle(count: count, radius: value, facesOut: facesOut), coalesce: "clone-radius")
            }
            Toggle("Facing out", isOn: Binding(get: { facesOut }, set: { set(.circle(count: count, radius: radius, facesOut: $0)) }))
        case let .line(count, step):
            Stepper("Copies \(count)", value: self.count(count) { .line(count: $0, step: step) }, in: 2 ... 200)
            spacingSlider(step.length) { .line(count: count, step: (step.length > 1e-9 ? step.normalized : .unitX) * $0) }
        case let .path(count, path, along):
            Stepper("Copies \(count)", value: self.count(count) { .path(count: $0, path: path, along: along) }, in: 2 ... 200)
            Picker("Path", selection: Binding(get: { path }, set: { set(.path(count: count, path: $0, along: along)) })) {
                ForEach(drawnPaths, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
            }
            Toggle("Turned along it", isOn: Binding(get: { along }, set: { set(.path(count: count, path: path, along: $0)) }))
        }
    }

    private var drawnPaths: [SceneObject] {
        editor.baseScene.objects.values.filter { if case .drawing = $0.kind { return $0.id != object.id } else { return false } }
            .sorted { $0.name < $1.name }
    }

    private func count(_ value: Int, _ layout: @escaping (Int) -> ObjectClones.Layout) -> Binding<Int> {
        Binding(get: { value }, set: { set(layout($0)) })
    }

    private func spacingSlider(_ value: Double, _ layout: @escaping (Double) -> ObjectClones.Layout) -> some View {
        LabeledSlider(title: "Spacing", value: value, range: 0.05 ... 10, format: { NumberFormat.short($0) + " m" }) {
            set(layout($0), coalesce: "clone-spacing")
        }
    }

    private func set(_ layout: ObjectClones.Layout, coalesce: String? = nil) {
        editor.updateClones(of: object.id, coalesce: coalesce) { $0.layout = layout }
    }

    /// A new layout from its name, keeping the count and size where they carry over.
    private func setLayout(_ title: String) {
        let count = min(clones.count, 50)
        let gap = { () -> Double in
            if case let .grid(_, _, _, spacing) = clones.layout { return spacing.x }
            if case let .line(_, step) = clones.layout { return step.length }
            return 1.4
        }()
        switch title {
        case "Circle": set(.circle(count: max(count, 3), radius: gap * Double(max(count, 3)) / (2 * .pi), facesOut: true))
        case "Line": set(.line(count: max(count, 2), step: Vec3(gap, 0, 0)))
        case "Along a path":
            guard let path = drawnPaths.first else { return editor.app.show("Draw a path first (Draw, then a line), and choose it here") }
            set(.path(count: max(count, 2), path: path.id, along: true))
        default: set(.grid(columns: 5, rows: 5, layers: 1, spacing: Vec3(gap, gap, gap)))
        }
    }
}

/// One effect: what it does and where it reaches.
private struct CloneEffectRow: View {
    let editor: EditorModel
    let object: SceneObject
    let effect: CloneEffect
    let index: Int
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HStack {
                Text(LocalizedStringKey(effect.kind.title)).font(.hmm(.body, weight: .semibold))
                Spacer()
                HmmButton("minus.circle", label: "Remove the effect", size: 32) { change { $0.effects.remove(at: index) } }
            }
            switch effect.kind {
            case .random:
                slider("Up and down", effect.move.y, 0 ... 3, unit: " m") { $0.move.y = $1 }
                slider("Turn", effect.turn.y, 0 ... 180, unit: "°") { $0.turn.y = $1 }
                slider("Size", effect.grow, 0 ... 1, unit: nil) { $0.grow = $1 }
            case .delay:
                slider("Between copies", effect.delay, 0 ... 0.5, unit: " s") { $0.delay = $1 }
            case .push:
                slider("Up", effect.move.y, -3 ... 3, unit: " m") { $0.move.y = $1 }
                slider("Grow", effect.grow, -1 ... 2, unit: nil) { $0.grow = $1 }
            }
            fieldPicker
        }
        .padding(HmmSpacing.s)
        .background(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous).fill(theme.surface2))
    }

    private var fieldPicker: some View {
        Picker("Where", selection: Binding(get: { effect.field.title }, set: { title in
            change { clones in
                clones.effects[index].field = switch title {
                case "Near a point": .sphere(centre: .zero, radius: 2)
                case "Ripple": .wave(speed: 3, width: 1.5, every: 2)
                default: .everywhere
                }
            }
        })) {
            ForEach(["Everywhere", "Near a point", "Ripple"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
        }
        .accessibilityIdentifier("clone-field-\(index)")
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, unit: String?,
                        _ write: @escaping (inout CloneEffect, Double) -> Void) -> some View {
        LabeledSlider(
            title: title,
            value: value,
            range: range,
            format: { number in unit.map { NumberFormat.short(number) + $0 } ?? NumberFormat.percent(number) }
        ) { new in
            change(coalesce: "clone-effect-\(effect.id)-\(title)") { write(&$0.effects[index], new) }
        }
    }

    private func change(coalesce: String? = nil, _ edit: @escaping (inout ObjectClones) -> Void) {
        editor.updateClones(of: object.id, coalesce: coalesce) { clones in
            guard clones.effects.indices.contains(index) else { return }
            edit(&clones)
        }
    }
}
