import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// A made character for games (K1 step 6), formats first: **For an engine** (Godot, Unity or Unreal: the skeleton named
/// for that engine's humanoid retargeting, face states as blend shapes, named clips, LODs, a capsule, real metres),
/// **Sprite sheet** (4 or 8 directions, the motions it plays, pixel art), **Turnaround** (front, three-quarter, side,
/// back). The file lands in the project's renders and the share sheet opens.
struct GameExportSheet: View {
    @Bindable var editor: EditorModel
    @AppStorage("gameExport.engine") private var engine = GameEngine.godot.rawValue
    @State private var sharing: [URL] = []
    @Environment(\.hmmTheme) private var theme

    private var person: Bool {
        editor.gameCharacter.flatMap { editor.baseScene.objects[$0]?.rig?.standard } == .humanoid
    }

    var body: some View {
        HmmSheet("For games") {
            if editor.gameCharacter == nil {
                HmmEmptyState("figure.stand", title: "Pick a character", message: "Select the character to export, then come back.")
            } else {
                engineSection
                spriteSection
                turnaroundSection
                if let working = editor.maker.working {
                    HStack { ProgressView(); Text(verbatim: working).font(.hmm(.footnote)).foregroundStyle(theme.text2) }
                }
            }
        }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) { ShareSheet(items: sharing) }
    }

    private var engineSection: some View {
        PanelSection("For an engine") {
            Picker("Engine", selection: $engine) {
                ForEach(GameEngine.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("game-engine")
            Text(person ? "A humanoid skeleton named for its retargeting, the face as blend shapes, the ten humanoid clips and its own, LODs and a capsule."
                : "Its skeleton, the face as blend shapes, its clips, LODs and a capsule.")
                .font(.hmm(.footnote)).foregroundStyle(theme.text2)
            HmmPillButton("Export GLB", systemName: "cube.transparent", prominent: true) {
                if let url = editor.exportForGame(GameEngine(rawValue: engine) ?? .godot) { sharing = [url] }
            }
            .accessibilityIdentifier("game-export-glb")
        }
    }

    private var spriteSection: some View {
        PanelSection("Sprite sheet") {
            Picker("Directions", selection: $editor.maker.sprites.eightDirections) {
                Text("4 directions").tag(false)
                Text("8 directions").tag(true)
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(motionNames, id: \.self) { name in
                        ChoiceChip(title: name, isOn: editor.maker.sprites.motions.contains(name)) {
                            if let index = editor.maker.sprites.motions.firstIndex(of: name) {
                                editor.maker.sprites.motions.remove(at: index)
                            } else {
                                editor.maker.sprites.motions.append(name)
                            }
                        }
                        .accessibilityIdentifier("sprite-motion-\(name)")
                    }
                }
            }
            Picker("Frame size", selection: $editor.maker.sprites.size) {
                ForEach([64, 128, 256], id: \.self) { Text(verbatim: "\($0) px").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Pixel art", isOn: $editor.maker.sprites.pixelArt)
                .accessibilityIdentifier("sprite-pixel-art")
            if editor.maker.sprites.pixelArt {
                Picker("Pixels tall", selection: $editor.maker.sprites.pixelHeight) {
                    ForEach([24, 32, 48, 64], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HmmPillButton("Export sprite sheet", systemName: "square.grid.3x3", prominent: true) {
                Task { if let url = await editor.exportSprites() { sharing = [url] } }
            }
            .disabled(editor.maker.working != nil)
            .accessibilityIdentifier("game-export-sprites")
        }
    }

    /// What a sheet can play: standing still, its own timeline, and for a person the humanoid clips.
    private var motionNames: [String] {
        ["Still", "Timeline"] + (person ? BuiltinClips.names : [])
    }

    private var turnaroundSection: some View {
        PanelSection("Turnaround") {
            HmmPillButton("Export turnaround", systemName: "rotate.3d") {
                Task { if let url = await editor.exportTurnaround() { sharing = [url] } }
            }
            .disabled(editor.maker.working != nil)
            .accessibilityIdentifier("game-export-turnaround")
        }
    }
}
