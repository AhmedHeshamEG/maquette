import HmmDesign
import HmmMedia
import LoweyCore
import LoweyEngine
import SwiftUI

/// Export asks formats first (A1, CONTEXT §10.11): Video · Picture · 3D · Paper, then the format (MP4, ProRes 4444,
/// render passes; glTF, FBX, 3MF; PDF…), then its named presets (glTF ▸ for Godot, FBX ▸ for Unity…), the last one
/// used already picked. Final, transparency, only the selection and every scene or shot are options beside them. It
/// renders in the background with the stage still usable, carries on when you leave the app, and every video is
/// checked before it counts as done.
struct ExportSheet: View {
    @Bindable var editor: EditorModel
    @AppStorage("export.category") private var category = ExportCategory.video
    @AppStorage("export.format") private var lastFormat = ExportFormat.mp4.rawValue
    @AppStorage("export.preset") private var lastPreset = ExportPreset.hd1080.rawValue
    @State private var format: ExportFormat = .mp4
    @State private var preset: ExportPreset = .hd1080
    @State private var settings = ExportPreset.hd1080.settings(range: TimeRange(start: 0, end: 1), fps: 30)
    @State private var options = ExportOptions()
    @State private var sharing: [URL] = []
    /// Whether this iPad writes ProRes (asked once, by writing two small frames).
    @State private var proRes = false
    /// Whether it writes 10-bit HDR HEVC (F1).
    @State private var hdr = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("Export") {
            categories
            formats
            Text(LocalizedStringKey(format.purpose)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: HmmSpacing.xs)], spacing: HmmSpacing.xs) {
                ForEach(format.presets.filter { hdr || !$0.settings(range: range, fps: 30).codec.isHDR }) { item in
                    TileButton(title: ExportPreset.title(of: item), systemName: ExportPreset.symbol(of: item), identifier: "export-\(item.rawValue)",
                               isOn: preset == item) { choose(item) }
                }
            }
            if let note = ExportPreset.note(of: preset) {
                Text(LocalizedStringKey(note)).font(.hmm(.footnote)).foregroundStyle(theme.text2).accessibilityIdentifier("export-note")
            }
            ExportOptionsView(editor: editor, preset: preset, settings: $settings, options: $options)
            Text(LocalizedStringKey(summary)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            progressOrStart
            results
        }
        .onAppear { open(category, remembered: true) }
        .task {
            proRes = await ExportCapabilities.proRes()
            hdr = await ExportCapabilities.hdr()
        }
        .onChange(of: options.onlyLoop) { _, _ in settings.range = range }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) { ShareSheet(items: sharing) }
    }

    private var range: TimeRange {
        options.onlyLoop ? (editor.timeline.loop ?? TimeRange(start: 0, end: editor.timeline.duration)) : TimeRange(start: 0, end: editor.timeline.duration)
    }

    /// Video, Picture, 3D, Paper: the first choice.
    private var categories: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(ExportCategory.allCases) { item in
                ChoiceChip(title: item.title, systemName: item.systemImage, isOn: category == item) {
                    withHmmAnimation(.snappy) { open(item, remembered: false) }
                }
                .accessibilityIdentifier("export-kind-\(item.rawValue)")
            }
        }
    }

    /// The category's formats this iPad can write (ProRes needs its media engine; FBX a rigged thing; maps paint).
    private var formats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(available(category)) { item in
                    ChoiceChip(title: item.title, systemName: nil, isOn: format == item) {
                        withHmmAnimation(.snappy) { pick(item) }
                    }
                    .accessibilityIdentifier("export-format-\(item.rawValue)")
                }
            }
        }
    }

    private func available(_ category: ExportCategory) -> [ExportFormat] {
        category.formats.filter { item in
            switch item {
            case .prores: proRes
            case .spatialVideo: SpatialVideoEncoder.isSupported
            case .fbx: editor.canExportFBX
            case .maps: editor.hasPaintedThings
            case .captions: !editor.timeline.transcripts.isEmpty
            case .ifc, .drawings: Held.isOn(.buildingFiles) && editor.hasBuilding
            case .technical: Held.isOn(.technicalSheets)
            case .papercraft: Held.isOn(.papercraft)
            default: true
            }
        }
    }

    /// Opens a category on its last format and preset (or its first).
    private func open(_ item: ExportCategory, remembered: Bool) {
        category = item
        let formats = available(item)
        let last = ExportFormat(rawValue: lastFormat).flatMap { formats.contains($0) ? $0 : nil }
        pick(last ?? formats.first ?? .mp4)
        if remembered, let saved = ExportPreset(rawValue: lastPreset), saved.format == format { choose(saved) }
    }

    private func pick(_ item: ExportFormat) {
        format = item
        lastFormat = item.rawValue
        if let first = item.presets.first { choose(first) }
    }

    private func choose(_ item: ExportPreset) {
        preset = item
        lastPreset = item.rawValue
        settings = item.settings(range: range, fps: editor.timeline.fps, frame: editor.timeline.frameShape)
        options.transparent = settings.transparent
    }

    private var summary: String {
        switch preset.kind {
        case .video, .gif, .frames, .passes:
            let size = settings.size
            return "\(size.width) × \(size.height) · \(settings.fps) fps · \(NumberFormat.short(settings.range.duration)) s · \(settings.frameCount) frames"
                + (settings.transparent ? " · transparent" : "") + (settings.final ? " · Final" : "")
        case .still, .stillPasses: return "The frame at the playhead, through the shot camera."
        case .model: return (options.onlySelection ? "The selection. " : "The whole scene. ") + (format.modelFormat?.purpose ?? "")
        case .lookShader: return "The \(editor.lookPreset.name) Look, with LICENSE.txt: use it in anything, commercial included."
        case .paper: return preset.paper?.frames == true ? "Nine frames across the shot, with their moments." : "The frame at the playhead."
        case .captions: return "Subtitles (.srt and .vtt) from the transcript."
        case .animatic, .spatialVideo, .video360:
            let size = settings.size
            return "\(size.width) × \(size.height) · \(settings.fps) fps · \(NumberFormat.short(settings.range.duration)) s"
                + (preset.kind == .animatic ? " · \(editor.timeline.shots(in: settings.range).count) shots held" : "")
        case .spatialPhoto, .panorama: return "The frame at the playhead, all around or in depth."
        case .storyboard: return "\(editor.timeline.shots().count) shots, three to a row."
        case .guest: return (options.onlySelection ? "The selection. " : "The whole scene. ") + format.purpose
        }
    }

    @ViewBuilder private var progressOrStart: some View {
        if let progress = editor.exportProgress {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                ProgressView(value: progress)
                HStack {
                    Text(editor.exportWaiting ? "Waiting while the app is in the background. It carries on when you're back."
                        : "Rendering \(Int(progress * 100))%. You can keep working.")
                        .font(.hmm(.footnote)).foregroundStyle(editor.exportWaiting ? theme.accent : theme.text2)
                    Spacer()
                    HmmPillButton("Cancel", role: .destructive) { editor.cancelExport() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export-progress")
        } else {
            HmmPillButton("Export", systemName: "square.and.arrow.up", prominent: true) {
                editor.startExport(options.job(preset, settings: settings))
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("export-start")
        }
    }

    @ViewBuilder private var results: some View {
        if !editor.exportResults.isEmpty {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                ForEach(editor.exportResults, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc").font(.hmm(.footnote)).lineLimit(1)
                }
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Share", systemName: "square.and.arrow.up") { sharing = editor.exportResults }
                    HmmPillButton("Save to Photos", systemName: "photo.on.rectangle") { editor.saveToPhotos(editor.exportResults) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export-results")
        }
    }
}

/// What this iPad can write, asked once a launch.
@MainActor
enum ExportCapabilities {
    private static var writesProRes: Bool?

    static func proRes() async -> Bool {
        if let writesProRes { return writesProRes }
        let answer = await VideoEncoder.canEncode(.prores4444)
        writesProRes = answer
        return answer
    }

    private static var writesHDR: Bool?

    static func hdr() async -> Bool {
        if let writesHDR { return writesHDR }
        let answer = await VideoEncoder.canEncode(.hevcHDR)
        writesHDR = answer
        return answer
    }
}
