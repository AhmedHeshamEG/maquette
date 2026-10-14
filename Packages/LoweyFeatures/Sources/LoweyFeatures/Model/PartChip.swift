import HmmDesign
import LoweyCore
import SwiftUI

/// The picked part's chip (U6: one obvious move by dragging, the rest one step deeper). A face: inset, shell, bridge
/// (two faces), knife. An edge: bevel, round, loop cut, knife. Corners: merge, fill the hole. Each: the pivot here, and
/// the pick grown, shrunk or made similar. A sketch region: sweep, revolve, loft. Sketch lines: their rules.
struct PartChip: View {
    @Bindable var editor: EditorModel

    var body: some View {
        GeometryReader { geometry in
            if let rect = editor.pickedPartRect, hasContent {
                chip
                    .fixedSize()
                    .position(x: min(max(rect.midX, 190), geometry.size.width - 190), y: max(rect.minY - 44, 96))
            }
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

extension EditorModel {
    /// Where the picked part is on screen (corners of the picked faces, edges or corners; a region's outline; the
    /// picked sketch lines).
    var pickedPartRect: CGRect? {
        _ = viewRevision
        guard let stage else { return nil }
        var points: [CGPoint] = []
        if let id = modeling.target, let elements = modeling.elements, let (mesh, world) = modelMesh(of: id) {
            points = elements.touchedVertices(in: mesh).filter(mesh.vertices.indices.contains)
                .compactMap { stage.screenPoint(of: world.apply(to: mesh.vertices[$0])) }
        } else if let region = modeling.region, let sketch = sketch(region.sketch), let shape = sketch.regions[safe: region.index] {
            points = shape.outline.compactMap { stage.screenPoint(of: sketch.plane.lift($0)) }
        } else {
            for ref in modeling.ruleCurves {
                guard let sketch = sketch(ref.sketch), let curve = sketch.curves[safe: ref.index] else { continue }
                points += curve.points.compactMap { stage.screenPoint(of: sketch.plane.lift($0)) }
            }
        }
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
