import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// 3D text's font (the style's, or one brought in) and letters that animate from a preset (D1).
struct TextDesignRows: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: TextRecipe
    @State private var importingFont = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            fontMenu
            Text("Letters").font(.hmm(.footnote, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    chip("None", systemName: "textformat", on: letters == nil) { editor.setLetters(nil, for: object.id) }
                    ForEach(TextAnimator.Preset.allCases) { preset in
                        chip(preset.title, systemName: preset.systemImage, on: letters?.preset == preset) { editor.setLetters(preset, for: object.id) }
                            .accessibilityIdentifier("letters-\(preset.rawValue)")
                    }
                }
            }
            if let letters { letterNumbers(letters) }
        }
        .fileImporter(isPresented: $importingFont, allowedContentTypes: [.font]) { result in
            if case let .success(url) = result { editor.importFont(url, for: object.id) }
        }
    }

    private var letters: TextAnimator? { object.motionDesign?.letters }

    private var fontMenu: some View {
        Menu {
            Button("The style's font") { editor.setFont(nil, for: object.id) }
            ForEach(editor.projectFonts, id: \.file) { font in
                Button { editor.setFont(font.file, for: object.id) } label: { Text(verbatim: font.name) }
            }
            Divider()
            Button("Bring in a font…", systemImage: "plus") { importingFont = true }
        } label: {
            Label(fontName, systemImage: "textformat.alt").font(.hmm(.body, weight: .semibold))
        }
        .accessibilityIdentifier("text-font")
    }

    private var fontName: String {
        guard let file = recipe.font else { return String(localized: "Font: the style's") }
        let name = editor.projectFonts.first { $0.file == file }?.name ?? (file as NSString).lastPathComponent
        return String(localized: "Font: \(name)")
    }

    @ViewBuilder
    private func letterNumbers(_ letters: TextAnimator) -> some View {
        Picker("Order", selection: Binding(get: { letters.order }, set: { order in editor.updateLetters(of: object.id) { $0.order = order } })) {
            ForEach(TextAnimator.Order.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
        }
        LabeledSlider(title: "Between letters", value: letters.stagger, range: 0 ... 0.4, format: { NumberFormat.short($0) + " s" }) { value in
            editor.updateLetters(of: object.id, coalesce: "letters-stagger") { $0.stagger = value }
        }
        LabeledSlider(title: letters.preset.repeats ? "One wave" : "Each letter", value: letters.length, range: 0.05 ... 3,
                      format: { NumberFormat.short($0) + " s" }) { value in
            editor.updateLetters(of: object.id, coalesce: "letters-length") { $0.length = value }
        }
        Hint(letters.preset.repeats ? "The wave keeps going. Match one wave to the loop for a seamless loop."
            : "They start at \(TimeFormat.clock(letters.start)). Choose the preset again to start them at the playhead.")
    }

    private func chip(_ title: String, systemName: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: systemName).font(.hmm(.footnote, weight: .semibold))
                .padding(.horizontal, HmmSpacing.s).frame(minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(on ? Color.accentColor : Color.secondary)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A morph (D1): what it becomes, and taking it back.
struct MorphRow: View {
    let editor: EditorModel
    let object: SceneObject
    let morph: ObjectMorph

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Label("Becomes \(editor.baseScene.objects[morph.target]?.name ?? "?")", systemImage: "wand.and.rays").font(.hmm(.body, weight: .semibold))
            Hint("Its Morph keys say when. The shape it becomes is hidden; show it from the outliner.")
            HmmPillButton("Remove the morph", systemName: "xmark.bin", role: .destructive) { editor.removeMorph(of: object.id) }
                .accessibilityIdentifier("morph-remove")
        }
    }
}

/// Make it move ▸ Links (D1): what moves this thing, a link made by tapping the thing that drives it, or the music.
struct LinksSection: View {
    let editor: EditorModel
    let object: SceneObject
    @State private var feature = MotionLink.SoundFeature.beat
    @State private var channel = MotionLink.Channel.moveY

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            ForEach(editor.links(of: object.id)) { link in
                VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                    HStack {
                        Text("\(link.channel.title) ← \(editor.driverName(link))").font(.hmm(.footnote, weight: .semibold))
                        Spacer()
                        HmmButton("minus.circle", label: "Remove the link", size: 32) { editor.removeLink(link.id) }
                    }
                    LabeledSlider(title: "How much", value: link.amount, range: Self.range(link), format: NumberFormat.short) { value in
                        editor.updateLink(link.id, coalesce: "link-\(link.id)") { $0.amount = value }
                    }
                }
            }
            Menu {
                ForEach(LinkPreset.allCases) { preset in
                    Button(LocalizedStringKey(preset.title), systemImage: preset.systemImage) { editor.beginLink(preset) }
                }
            } label: {
                Label("Link to another thing…", systemImage: "link").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("link-thing")
            if !editor.timeline.audio.isEmpty { music }
        }
    }

    private var music: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Picker("To the sound's", selection: $feature) {
                ForEach(MotionLink.SoundFeature.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            Picker("It", selection: $channel) {
                ForEach(MotionLink.Channel.allCases.filter { $0 != .effect || object.motionDesign?.clones != nil }) {
                    Text(LocalizedStringKey($0.title)).tag($0)
                }
            }
            Menu {
                ForEach(editor.timeline.audio) { clip in
                    Button { editor.linkToSound(clip.id, feature: feature, channel: channel) } label: { Text(verbatim: clip.name) }
                }
            } label: {
                Label("Move to the music…", systemImage: "waveform").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("link-music")
            if editor.timeline.audio.contains(where: { editor.isMeasuring($0.id) }) {
                ProgressView().accessibilityLabel("Listening to the sound")
            }
        }
    }

    static func range(_ link: MotionLink) -> ClosedRange<Double> {
        switch link.channel {
        case .turnX, .turnY, .turnZ: if case .sound = link.driver { return -180 ... 180 } else { return -4 ... 4 }
        case .glow: return 0 ... 10
        default: return -3 ... 3
        }
    }
}
