import HmmDesign
import LoweyCore
import SwiftUI

/// The picked part's chip (U6: one obvious move by dragging, the rest one step deeper), docked above the tool's bar. A face: inset, shell, bridge
/// (two faces), knife. An edge: bevel, round, loop cut, knife. Corners: merge, fill the hole. Each: the pivot here, and
/// the pick grown, shrunk or made similar. A sketch region: sweep, revolve, loft. Sketch lines: their rules.
struct PartChip: View {
    @Bindable var editor: EditorModel

    var body: some View {
        // Docked above the tool's bar, never over the work: the pick's floating numbers (a pull, a size) stay free to tap.
        if hasContent {
            VStack {
                Spacer(minLength: 0)
                chip.fixedSize()
            }
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity)
        }
    }

    private var hasContent: Bool {
        editor.modeling.elements.map { !$0.isEmpty } ?? false || editor.modeling.region != nil || !editor.availableRules.isEmpty
    }

    private var chip: some View {
        HStack(spacing: HmmSpacing.xxs) {
            if !editor.availableRules.isEmpty {
                rules
            } else if editor.modeling.region != nil {
                profile
            } else if let elements = editor.modeling.elements {
                part(elements)
            }
            HmmButton("xmark", label: "Done", size: 40) {
                editor.clearModelPick()
                editor.modeling.ruleCurves = []
                editor.refreshModelOverlay()
            }
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("part-chip")
    }

    @ViewBuilder
    private func part(_ elements: MeshSelection) -> some View {
        switch elements.mode {
        case .face:
            HmmButton("square.inset.filled", label: "Inset", size: 40) { editor.insetPick() }
                .accessibilityIdentifier("inset")
            HmmButton("cube.box", label: "Shell, leaving these open", size: 40) { editor.shellPick() }
                .accessibilityIdentifier("shell-open")
            if elements.faces.count == 2 {
                HmmButton("rectangle.connected.to.line.below", label: "Bridge", size: 40) { editor.bridgePickedFaces() }
                    .accessibilityIdentifier("bridge")
            }
            knife
        case .edge:
            HmmButton("square.bottomhalf.filled", label: "Bevel", size: 40) { editor.bevelPick(.chamfer) }
                .accessibilityIdentifier("bevel")
            HmmButton("app", label: "Round", size: 40) { editor.bevelPick(.round) }
                .accessibilityIdentifier("round")
            HmmButton("rectangle.split.2x1", label: "Loop cut", size: 40) { editor.loopCutPickedEdge() }
                .accessibilityIdentifier("loop-cut")
            knife
        case .vertex:
            if elements.vertices.count >= 2 {
                HmmButton("arrow.down.right.and.arrow.up.left", label: "Merge", size: 40) { editor.mergePickedCorners() }
                    .accessibilityIdentifier("merge")
            }
            HmmButton("circle.dashed.inset.filled", label: "Fill the hole", size: 40) { editor.fillHolesOfSelection() }
                .accessibilityIdentifier("fill-hole")
        }
        Menu {
            Button("Grow the pick", systemImage: "plus.magnifyingglass") { editor.growPick() }
            Button("Shrink the pick", systemImage: "minus.magnifyingglass") { editor.shrinkPick() }
            Button("Pick the similar ones", systemImage: "square.grid.3x3.square") { editor.selectSimilarElements() }
            Button("Move the pivot here", systemImage: "scope") { editor.movePivotToPick() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("part-more")
    }

    private var knife: some View {
        HmmButton("scissors", label: "Knife: draw a line across", isOn: editor.modeling.knifeArmed, size: 40) {
            if editor.tool != .model { editor.chooseModelVerb(.shape) }
            editor.modeling.knifeArmed.toggle()
            if editor.modeling.knifeArmed { editor.app.show("Draw a line across the shape to cut it") }
        }
        .accessibilityIdentifier("knife")
    }

    @ViewBuilder private var profile: some View {
        switch editor.modeling.awaiting {
        case .revolve:
            Text("Tap the line to turn around").font(.hmm(.footnote)).padding(.horizontal, HmmSpacing.xs)
            HmmPillButton("Around its side", systemName: "arrow.triangle.2.circlepath") { editor.revolveAroundSide() }
                .accessibilityIdentifier("revolve-side")
        case let .loft(regions):
            Text("\(regions.count) shapes").font(.hmm(.footnote)).monospacedDigit().padding(.horizontal, HmmSpacing.xs)
            HmmPillButton("Loft", systemName: "cone") { editor.finishLoft() }
                .accessibilityIdentifier("loft-done")
        case .sweep:
            Text("Tap the path to sweep along").font(.hmm(.footnote)).padding(.horizontal, HmmSpacing.xs)
        case nil:
            HmmButton("point.topleft.down.to.point.bottomright.curvepath", label: "Sweep along a path", size: 40) { editor.startSweep() }
                .accessibilityIdentifier("sweep")
            HmmButton("arrow.triangle.2.circlepath", label: "Revolve around a line", size: 40) { editor.startRevolve() }
                .accessibilityIdentifier("revolve")
            HmmButton("cone", label: "Loft through shapes", size: 40) { editor.startLoft() }
                .accessibilityIdentifier("loft")
        }
    }

    private var rules: some View {
        ForEach(editor.availableRules) { rule in
            HmmButton(rule.systemImage, label: rule.title, size: 40) { editor.applyRule(rule) }
                .accessibilityIdentifier("rule-\(rule.rawValue)")
        }
    }
}
