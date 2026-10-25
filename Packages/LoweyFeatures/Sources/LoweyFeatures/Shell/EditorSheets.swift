import HmmDesign
import LoweyCore
import SwiftUI

/// The editor's sheets, one at a time (`EditorModel.sheet`).
struct EditorSheets: ViewModifier {
    @Bindable var editor: EditorModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.sheet(item: $editor.sheet) { sheet in
            sheetContent(sheet)
                .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: UserDefaults.standard.string(forKey: HmmThemeMode.storageKey) ?? "") ?? .dark)
        }
        .sheet(item: Binding(get: { editor.ar.share.map(IdentifiedURL.init) }, set: { editor.ar.share = $0?.url })) { ShareSheet(items: [$0.url]) }
        // The bridge's `app monitor` (M12): only a view can open a window.
        .onChange(of: editor.ar.monitorRequested) { _, asked in
            guard asked else { return }
            editor.ar.monitorRequested = false
            openWindow(id: LoweyWindow.monitor)
        }
        // M12: the scene in the room fills the screen.
        .fullScreenCover(isPresented: $editor.ar.open) {
            ARScreen(editor: editor)
                .hmmThemed(.lowey, mode: .dark)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .export: ExportSheet(editor: editor).presentationDetents([.large])
        case .audio: AudioSheet(editor: editor).presentationDetents([.medium, .large])
        case .transcript: TranscriptSheet(editor: editor).presentationDetents([.medium, .large])
        case .scripts: ScriptSheet(editor: editor).presentationDetents([.large])
        case .bridge: BridgeSheet(bridge: editor.app.bridge, editor: editor).presentationDetents([.large])
        case .blobBuilder: BlobBuilderSheet(editor: editor).presentationDetents([.medium, .large])
        case .characterBuilder: CharacterBuilderSheet(editor: editor, editing: editor.characterBuilderTarget).presentationDetents([.large])
        case .settings: SettingsSheet(app: editor.app).presentationDetents([.large])
        case .diagnostics: DiagnosticsSheet(app: editor.app, editor: editor).presentationDetents([.large])
        case .gestures: NavigationStack { GestureGuide() }.presentationDetents([.large])
        case .learn: LearnSheet(app: editor.app).presentationDetents([.large])
        case .timelineSettings: TimelineSettingsSheet(editor: editor).presentationDetents([.medium])
        case .brushes: BrushLibrarySheet(editor: editor).presentationDetents([.large])
        case .gameExport: GameExportSheet(editor: editor).presentationDetents([.medium, .large])
        case .plans: PlanSheet(editor: editor).presentationDetents([.large])
        case .matchPhoto: PhotoMatchSheet(editor: editor).presentationDetents([.large])
        case .roomScan: RoomScanSheet(editor: editor).presentationDetents([.large])
        case .objectScan: ObjectScanSheet(editor: editor).presentationDetents([.large])
        case .phone: PhoneSheet(editor: editor).presentationDetents([.medium, .large])
        }
    }
}

/// Keyboard shortcuts without visible buttons (the menu bar shows them; ⌘-hold lists them).
struct EditorKeyboardShortcuts: View {
    let editor: EditorModel

    private func key(_ key: KeyEquivalent, _ modifiers: EventModifiers = [], _ action: @escaping () -> Void) -> some View {
        Button(action: action) { EmptyView() }
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    var body: some View {
        ZStack {
            key(.space) { editor.togglePlay() }
            key("j") { editor.jump(seconds: -1) }
            key("k") { editor.pause() }
            key("l") { editor.isPlaying ? editor.jump(seconds: 1) : editor.play() }
            key(.leftArrow, .option) { editor.jump(seconds: -10) }
            key(.rightArrow, .option) { editor.jump(seconds: 10) }
            key(.leftArrow) { editor.step(frames: -1) }
            key(.rightArrow) { editor.step(frames: 1) }
            key("[") { editor.nudgeSelectedKeys(frames: -1) }
            key("]") { editor.nudgeSelectedKeys(frames: 1) }
            key(.delete) { editor.selectedKeys.isEmpty ? editor.deleteSelection() : editor.deleteSelectedKeys() }
            key(.escape) {
                if editor.openPanel != nil { editor.openPanel = nil } else { editor.setSelection([]) }
            }
            key("?", .shift) { editor.sheet = .gestures }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
