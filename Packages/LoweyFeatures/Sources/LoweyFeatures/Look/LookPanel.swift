import HmmDesign
import LoweyCore
import SwiftUI

/// Look, in three short pages (progressive disclosure): **Style** (which Look, and the palette), **World** (the mood,
/// the light and sky, fine tuning) and **Finish** (the grain, outlines and film finishes, and how motion is drawn: smooth,
/// on twos, on threes). The page is remembered.
struct LookPanel: View {
    @Bindable var editor: EditorModel
    @State private var savingLook = false
    @State private var lookName = ""
    @State private var showsFineTune = false
    @AppStorage("look.page") private var page = LookPage.style

    private var look: Look { editor.look }

    var body: some View {
        HmmPanel("Look", width: 380, sizing: HmmPanelSizing(id: "look"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                pages
                switch page {
                case .style:
                    looks
                    if let mine = editor.document.project.customLooks.first(where: { $0.id == look.presetID }) {
                        MyLookEditor(editor: editor, preset: mine)
                    }
                    PaletteSection(editor: editor)
                case .world:
                    moods
                    AirSection(editor: editor)
                    DisclosureGroup("Fine tune the world", isExpanded: $showsFineTune) {
                        WorldSection(editor: editor).padding(.top, HmmSpacing.xs)
                    }
                    .font(.hmm(.body, weight: .semibold))
                    saved
                case .finish:
                    FinishSection(editor: editor)
                    MotionFinish(editor: editor)
                    ScreenEffectsFinish(editor: editor)
                }
                Toggle("Only this scene", isOn: Binding(get: { editor.lookIsSceneOnly }, set: { editor.setLookSceneOnly($0) }))
                    .font(.hmm(.body, weight: .semibold))
            }
        }
        .alert("Save the world to your library", isPresented: $savingLook) {
            TextField("Name", text: $lookName)
            Button("Save") {
                let name = lookName.isEmpty ? "My world" : lookName
                Task { await editor.library.saveLook(look, name: name) }
                editor.app.show("Saved “\(name)” to your library")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var pages: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(LookPage.allCases) { item in
                ChoiceChip(title: item.title, systemName: item.systemImage, isOn: page == item) {
                    withHmmAnimation(.snappy) { page = item }
                }
                .accessibilityIdentifier("look-\(item.rawValue)")
            }
        }
    }

    private var looks: some View {
        PanelSection("Look") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(editor.allLooks) { preset in
                        Button {
                            editor.setLookPreset(preset.id)
                        } label: {
                            LookCard(preset: preset, selected: preset.id == look.presetID, mood: look.lightingPreset ?? .day)
                        }
                        .buttonStyle(.plain)
                        .hmmHoldMenu(HmmHoldMenu(duplicate: { editor.duplicateLook(preset) },
                                                 delete: holdAction(if: !preset.isBuiltIn) { editor.deleteCustomLook(preset.id) }))
                    }
                }
            }
            HStack {
                HmmPillButton("Duplicate as My Look", systemName: "plus.square.on.square") { editor.duplicateLook(editor.lookPreset) }
                    .accessibilityIdentifier("duplicate-look")
            }
            Hint("Touch and hold a Look for its options. Built-in Looks stay as they are; duplicate one to change it.")
        }
    }

    private var moods: some View {
        PanelSection("Mood") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(LightingPreset.allCases, id: \.self) { mood in
                        Button {
                            editor.setMood(mood)
                        } label: {
                            MoodCard(mood: mood, selected: look.lightingPreset == mood)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var saved: some View {
        PanelSection("Library") {
            HmmPillButton("Save this world to the library", systemName: "tray.and.arrow.down") {
                lookName = look.lightingPreset?.displayName ?? "My world"
                savingLook = true
            }
            let savedLooks = editor.library.manifest.looks
            if !savedLooks.isEmpty {
                ForEach(savedLooks) { saved in
                    Button(saved.name) { editor.place(.look(saved)) }.font(.hmm(.body))
                }
            }
        }
    }
}

/// Look's three pages.
enum LookPage: String, CaseIterable, Identifiable {
    case style, world, finish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: "Style"
        case .world: "World"
        case .finish: "Finish"
        }
    }

    var systemImage: String {
        switch self {
        case .style: "paintpalette"
        case .world: "sun.horizon"
        case .finish: "film"
        }
    }
}

/// Finish ▸ Motion: how the whole scene's motion is drawn (smooth, on twos, on threes). Any one thing can choose its
/// own in its panel (More ways to move ▸ Animated on).
struct MotionFinish: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Motion") {
            Picker("Motion", selection: Binding(get: { editor.timeline.stepping }, set: { editor.setProjectStepping($0) })) {
                Text("Smooth").tag(Stepping.onOnes)
                Text("On twos").tag(Stepping.onTwos)
                Text("On threes").tag(Stepping.onThrees)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("finish-motion")
            Hint("On twos looks hand-animated. Cameras stay smooth; any one thing can choose its own in its panel.")
        }
    }
}

/// Finish ▸ Screen effects (U5: the timeline's + Overlay went; screen finishes live in Look): a flash, a shake… at the
/// playhead.
struct ScreenEffectsFinish: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Screen effects at the playhead") {
            FlowChips(items: ScreenEffect.Kind.allCases.map { ($0.rawValue, $0.title) }, isOn: { _ in false }) { key in
                if let kind = ScreenEffect.Kind(rawValue: key) { editor.addScreenEffect(kind) }
            }
            .accessibilityIdentifier("finish-screen-effects")
        }
    }
}

/// The palette: linked colours (change one and everything using it follows), add and remove. The sidebar's Pick takes
/// a colour from the stage into the slot being edited.
struct PaletteSection: View {
    @Bindable var editor: EditorModel
    @State private var editingSlot: Int?
    @State private var slotColor = Color.white

    private var palette: Palette { editor.look.palette }

    var body: some View {
        PanelSection("Palette") {
            HStack {
                HmmButton("plus", label: "Add a colour", size: 36) { editor.addPaletteSwatch() }
                Spacer()
            }
            PaletteRow(palette: palette, selected: editingSlot, remove: { slot in
                if editingSlot == slot { editingSlot = nil }
                editor.removePaletteSwatch(slot)
            }) { slot in
                editingSlot = slot
                slotColor = palette.color(at: slot).color
                editor.currentColor = .palette(slot)
                editor.pickSlot = slot
            }
            if let slot = editingSlot, palette.swatches.indices.contains(slot) {
                ColorPicker(palette.swatches[slot].name, selection: $slotColor, supportsOpacity: false)
                    .onChange(of: slotColor) { _, value in
                        editor.updateLook(coalesce: "palette-\(slot)") { $0.palette.swatches[slot].color = RGBA(value) }
                    }
                Hint("Everything using this colour updates.")
            }
        }
    }
}
