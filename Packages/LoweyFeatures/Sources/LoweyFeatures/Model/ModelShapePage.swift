import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Edit: what is done to a solid. No buttons for faces, edges or corners (U6): the Pencil touches the part it
/// wants. The tiles put Model's verbs in the hand (Shape for hands, the brushes, the cage, a bend); then 3D printing.
/// Combine, mirror and the whole-shape tools are on the selection, in its panel; sketching is Draw ▸ Shapes.
struct ModelShapePage: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Shape it") {
                TileGrid {
                    ForEach([ModelVerb.shape, .brush, .cage, .bend]) { verb in
                        TileButton(title: verb.title, systemName: verb.systemImage, identifier: "model-verb-\(verb.rawValue)") {
                            editor.chooseModelVerb(verb)
                            editor.openPanel = nil
                        }
                    }
                }
                Hint("With a Pencil, touch a face, an edge or a corner of the selected thing and drag it. Tap one for more.")
            }
            PanelSection("3D print") {
                PrintCheckControls(editor: editor)
            }
        }
    }
}

/// Model's bar at the bottom of the stage (U6): Shape · Brush · Cage · Bend · Measure, then what the verb in the hand
/// needs (the brushes, the cage's points, the bend's kind and amount), then Done.
struct ModelOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            if editor.modeling.mode.pickMode != nil {
                ForEach(ModelVerb.allCases) { verb in
                    HmmButton(verb.systemImage, label: verb.title, isOn: editor.modeling.verb == verb, accent: editor.modeling.verb == verb, size: 40) {
                        editor.chooseModelVerb(verb)
                    }
                    .accessibilityIdentifier("model-verb-\(verb.rawValue)")
                }
                verbControls
            }
            ModelToolExtras(editor: editor)
            HmmButton("xmark", label: "Done modelling", size: 40) { editor.stopModeling() }
                .accessibilityIdentifier("model-done")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("model-bar")
    }

    @ViewBuilder private var verbControls: some View {
        switch editor.modeling.verb {
        case .brush: BrushControls(editor: editor)
        case .cage: CageControls(editor: editor)
        case .bend: BendControls(editor: editor)
        case .shape, .measure: EmptyView()
        }
    }
}

/// The brushes in the hand, and symmetry.
struct BrushControls: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Divider().frame(height: 24)
        ForEach(SculptBrush.allCases, id: \.self) { brush in
            HmmButton(Self.icon(brush), label: brush.title, isOn: editor.modeling.sculpt.brush == brush, size: 40) {
                editor.modeling.sculpt.brush = brush
            }
            .accessibilityIdentifier("sculpt-\(brush.rawValue)")
        }
        HmmButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror the strokes",
                  isOn: editor.modeling.sculpt.symmetry, size: 40) {
            editor.modeling.sculpt.symmetry.toggle()
        }
        .accessibilityIdentifier("sculpt-symmetry")
    }

    static func icon(_ brush: SculptBrush) -> String {
        switch brush {
        case .grab: "hand.draw"
        case .smooth: "water.waves"
        case .inflate: "circle.dotted.and.circle"
        }
    }
}

/// A cage on the selected thing: put one on, or reset it, or take it off.
struct CageControls: View {
    let editor: EditorModel

    var body: some View {
        Divider().frame(height: 24)
        if editor.shapedSelection?.shaping?.cage != nil {
            HmmButton("arrow.counterclockwise", label: "Every point back", size: 40) { editor.resetCage() }
                .accessibilityIdentifier("cage-reset")
            HmmButton("trash", label: "Take the cage off", size: 40, role: .destructive) { editor.removeCage() }
                .accessibilityIdentifier("cage-remove")
        } else {
            HmmPillButton("Put a cage on", systemName: "square.grid.3x3.square") { editor.addCage() }
                .accessibilityIdentifier("cage-add")
        }
    }
}

/// The whole-shape bend: its kind, its axis and how much.
struct BendControls: View {
    let editor: EditorModel
    @State private var gesture = UUID().uuidString

    var body: some View {
        Divider().frame(height: 24)
        if let object = editor.shapedSelection {
            let current = editor.bend(of: object)
            Menu {
                ForEach(Deform.allCases, id: \.self) { kind in
                    Button(LocalizedStringKey(kind.title)) { editor.setBend(kind) }
                }
                if current != nil { Button("No bend", role: .destructive) { editor.setBend(nil) } }
            } label: {
                Label(LocalizedStringKey(current?.kind.title ?? "Bend"), systemImage: "arrow.turn.up.right")
                    .font(.hmm(.footnote, weight: .semibold))
                    .frame(minHeight: 40)
                    .padding(.horizontal, HmmSpacing.s)
            }
            .accessibilityIdentifier("bend-kind")
            if let current {
                Menu {
                    ForEach(CoreAxis.allCases, id: \.self) { axis in
                        Button(axis.rawValue.uppercased()) { editor.setBendAxis(axis) }
                    }
                } label: {
                    Text(current.axis.rawValue.uppercased()).font(.hmm(.footnote, weight: .semibold)).frame(minWidth: 40, minHeight: 40)
                }
                .accessibilityLabel("Along \(current.axis.rawValue)")
                .accessibilityIdentifier("bend-axis")
                HmmNumberPill(current.kind.title, value: Binding(get: { current.amount }, set: { value in
                    editor.setBendAmount(value, gesture: gesture)
                }), scrub: HmmScrub(fine: current.kind == .bend || current.kind == .twist ? 1 : 0.01, range: current.kind.range),
                format: { Self.format($0, kind: current.kind) }, onEditingChanged: { editing in
                    if !editing {
                        editor.endGesture()
                        gesture = UUID().uuidString
                    }
                })
                .accessibilityIdentifier("bend-amount")
            }
        }
    }

    static func format(_ value: Double, kind: Deform) -> String {
        switch kind {
        case .bend, .twist: "\(Int(value.rounded()))°"
        case .taper, .bulge: "\(Int((value * 100).rounded())) %"
        }
    }
}
