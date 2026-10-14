import HmmDesign
import LoweyCore
import SwiftUI

/// Draw ▸ Sheets (U5): the sheets kept in the scene (draw on one again, a new one, rename, delete with its drawings)
/// and frames: lines drawn frame by frame on the sheet, Dreams' way (or stuck to the camera), with the flipbook's own
/// options and the ready-made drawn effects. Where the sheet stands, its shape and its guide are on its hold menu.
struct SheetsPopover: View {
    @Bindable var editor: EditorModel
    @State private var renaming: (id: String, name: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                sheets
                frames
            }
            .padding(HmmSpacing.m)
        }
        .frame(width: 340)
        .frame(maxHeight: 520)
        .font(.hmm(.body))
        .accessibilityIdentifier("sheets-popover")
        .alert("Rename the sheet", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }))
            Button("Rename") {
                if let renaming { editor.renameSheet(renaming.id, to: renaming.name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var sheets: some View {
        PanelSection("Sheets") {
            VStack(spacing: HmmSpacing.xxs) {
                ForEach(editor.baseScene.sheets) { sheet in row(sheet) }
            }
            HmmPillButton("New sheet", systemName: "plus") { editor.newSheet() }
                .accessibilityIdentifier("sheet-new")
            Hint("A finger's tap puts the sheet there: on a surface, or in the air facing you. Hold it for its shape and guide.")
        }
    }

    private func row(_ sheet: DrawingSheet) -> some View {
        let current = editor.currentSheet?.id == sheet.id
        return HStack(spacing: HmmSpacing.s) {
            Image(systemName: sheet.shape.systemImage).frame(width: 28)
            Text(verbatim: sheet.name).lineLimit(1)
            Spacer(minLength: 0)
            if current { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .padding(.horizontal, HmmSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { editor.chooseSheet(sheet.id) }
        .hmmHoldMenu(HmmHoldMenu(rename: { renaming = (sheet.id, sheet.name) }, extras: [], delete: { editor.deleteSheet(sheet.id) }))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("sheet-\(sheet.id)")
    }

    private var frames: some View {
        PanelSection("Frames") {
            Toggle("Draw frame by frame", isOn: Binding(get: { editor.drawFrames }, set: { editor.setDrawFrames($0) }))
                .accessibilityIdentifier("draw-frames")
            if editor.drawFrames {
                Toggle("Stuck to the camera", isOn: $editor.flipbook.onCamera)
                    .accessibilityIdentifier("flipbook-on-camera")
                FlowChips(items: trackChoices, isOn: { $0 == editor.flipbook.track }) { key in
                    if key == "new" { editor.startNewFlipbook() } else { editor.flipbook.track = key }
                }
                .accessibilityIdentifier("flipbook-tracks")
                if let track = editor.activeFlipbook { trackOptions(track) }
                if editor.flipbook.onCamera {
                    DrawingGuideControls(guide: editor.frameGuide, kinds: DrawingGuide.Kind.allCases, spacing: 0.01 ... 0.3,
                                         formatSpacing: { "\(Int(($0 * 100).rounded())) %" }) { editor.setFrameGuide($0) }
                }
                PanelSection("Drawn effects") {
                    FlowChips(items: FlipbookFX.allCases.map { ($0.rawValue, $0.title) }, isOn: { _ in false }) { key in
                        if let fx = FlipbookFX(rawValue: key) { editor.addFlipbookEffect(fx) }
                    }
                    Hint("On the selected object, else on the camera, starting at the playhead.")
                }
                Hint("Flick right with a finger for a new frame, left for the one before. The time at the bottom left shows the frames around this one.")
            }
        }
    }

    private var trackChoices: [(String, String)] {
        var choices: [(String, String)] = editor.flipbookTracks.map { track in (track.id, track.name) }
        choices.append(("new", String(localized: "New track")))
        return choices
    }

    private func trackOptions(_ track: FlipbookTrack) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Blend", selection: Binding(get: { track.blend }, set: { blend in editor.updateFlipbook("Blend") { $0.blend = blend } })) {
                ForEach(FlipbookBlend.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Track opacity", value: track.opacity, range: 0 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                          set: { value in editor.updateFlipbook("Opacity", coalesceKey: "flipbook-opacity") { $0.opacity = value } },
                          done: { editor.endGesture() })
            Toggle("Loop", isOn: Binding(get: { track.loops }, set: { loops in editor.updateFlipbook("Loop") { $0.loops = loops } }))
            Stepper("New drawings hold \(editor.flipbook.hold) frames", value: $editor.flipbook.hold, in: 1 ... 8)
            HmmPillButton("Delete track", systemName: "trash", role: .destructive) { editor.deleteFlipbook() }
        }
    }
}

/// Rename for the sheet, from its hold menu on the stage.
struct SheetRenameAlert: ViewModifier {
    @Bindable var editor: EditorModel
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("Rename the sheet", isPresented: Binding(get: { editor.renamingSheet != nil }, set: { if !$0 { editor.renamingSheet = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") {
                if let id = editor.renamingSheet { editor.renameSheet(id, to: name) }
                editor.renamingSheet = nil
            }
            Button("Cancel", role: .cancel) { editor.renamingSheet = nil }
        }
        .onChange(of: editor.renamingSheet) { _, id in
            name = id.flatMap { editor.baseScene.sheet($0)?.name } ?? ""
        }
    }
}
