import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Edit ▸ 3D print, set up for Print (G1): the part's way up, overhangs, split with pegs, hollow, scale to size,
/// holes and words where the Pencil taps, the fit between parts, the slicer, and a scan of an object.
struct PrintToolControls: View {
    @Bindable var editor: EditorModel
    @State private var size = ""
    @State private var sharing: [URL] = []
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Show overhangs", isOn: $editor.guest.overhangs).accessibilityIdentifier("print-overhangs")
            TileGrid {
                TileButton(title: "Best way up", systemName: "arrow.up.and.down.and.sparkles", identifier: "print-orient") { editor.orientForPrinting() }
                TileButton(title: "Split", systemName: "square.split.1x2", identifier: "print-split") { editor.splitForPrinting() }
                TileButton(title: "Hollow", systemName: "cube.transparent", identifier: "print-hollow") { editor.hollowForPrinting() }
                TileButton(title: BuildTool.hole.title, systemName: BuildTool.hole.systemImage, identifier: "print-hole") {
                    editor.startModeling(.build(.hole))
                    editor.openPanel = nil
                }
                TileButton(title: BuildTool.engrave.title, systemName: BuildTool.engrave.systemImage, identifier: "print-engrave") {
                    editor.startModeling(.build(.engrave))
                    editor.openPanel = nil
                }
                TileButton(title: "Share to the slicer", systemName: "printer", identifier: "print-slicer") {
                    if let url = editor.slicerFile() { sharing = [url] }
                }
                if ObjectScanSheet.isSupported {
                    TileButton(title: "Scan an object", systemName: "viewfinder", identifier: "print-scan") { editor.sheet = .objectScan }
                } else {
                    TileButton(title: "Scan with your iPhone", systemName: "iphone", identifier: "print-scan-phone") {
                        editor.ask(.objectScan)
                        editor.sheet = .phone
                    }
                }
            }
            Picker("Split across", selection: $editor.guest.splitAxis) {
                Text("Height").tag(CoreAxis.y)
                Text("Width").tag(CoreAxis.x)
                Text("Depth").tag(CoreAxis.z)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("print-split-axis")
            HStack(spacing: HmmSpacing.s) {
                Picker("Hole", selection: $editor.guest.hole) {
                    ForEach(ScrewHole.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                Picker("Screw", selection: $editor.guest.screw) {
                    ForEach(MetricScrew.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            TextField("Words to write", text: $editor.guest.text).textFieldStyle(.roundedBorder).accessibilityIdentifier("print-text")
            LabeledSlider(title: "Fit", value: editor.guest.tolerance * 1000, range: 0 ... 0.6, format: { String(format: "%.2f mm", $0) }) {
                editor.guest.tolerance = $0 / 1000
            }
            .accessibilityIdentifier("print-fit")
            HStack(spacing: HmmSpacing.xs) {
                TextField("Longest side", text: $size).textFieldStyle(.roundedBorder).keyboardType(.decimalPad).frame(maxWidth: 140)
                    .accessibilityIdentifier("print-size")
                HmmPillButton("Scale to size", systemName: "arrow.up.left.and.arrow.down.right") {
                    if let metres = try? LengthExpression.evaluate(size, defaultUnit: editor.units), metres > 0 { editor.scaleToSize(metres, axis: nil) }
                }
            }
            Hint("Split, hollow and scale work on the chosen part; a hole or words go where the Pencil taps it next.")
        }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) { ShareSheet(items: sharing) }
    }
}

/// Model ▸ Edit's Study and Game tools (G1): explode the chosen group (again: back together); freeze turns and sizes.
struct GuestEditSections: View {
    let editor: EditorModel

    var body: some View {
        switch editor.projectSetUp {
        case .study:
            PanelSection("Study") {
                TileGrid {
                    TileButton(title: "Explode", systemName: "square.3.layers.3d.down.forward", identifier: "study-explode",
                               isOn: editor.explodableGroup.flatMap { editor.baseScene.objects[$0]?.explodeAmount }.map { $0 > 0 } ?? false) {
                        editor.toggleExplode()
                    }
                    TileButton(title: "Forces", systemName: "arrow.up.right.and.arrow.down.left", identifier: "study-forces",
                               isOn: editor.physicsRun.showsArrows) {
                        editor.physicsRun.showsArrows.toggle()
                        editor.refreshPhysicsOverlay()
                    }
                }
                Hint("Choose a group of parts to explode; Forces shows the speed and force arrows of a run.")
                Hint("Export ▸ Paper ▸ Technical drawing makes the sheet with sizes and a parts list.")
            }
        case .game:
            PanelSection("Game") {
                TileGrid {
                    TileButton(title: "Freeze transforms", systemName: "snowflake", identifier: "game-freeze") { editor.freezeTransforms() }
                }
                Hint("Export ▸ 3D ▸ Game level writes the level the way Godot, Unity or Unreal reads it.")
            }
        default:
            EmptyView()
        }
    }
}
