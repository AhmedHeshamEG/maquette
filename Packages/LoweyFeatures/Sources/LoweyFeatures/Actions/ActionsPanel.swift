import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Actions in six (U9): Share · Windows · Notes open their own short page in the panel (a back arrow returns); History,
/// Learn and Settings open as they did. (The scenes are behind the scene's name; the assistant and scripts are in
/// Settings ▸ Assistant; sound and the timeline's settings live in the timeline.)
struct ActionsPanel: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var sharing: URL?
    @State private var page: Page?
    @AppStorage(AppSettings.boardEnabled) private var boardEnabled = true
    @Environment(\.openWindow) private var openWindow

    enum Page: String {
        case share, windows, notes

        var title: LocalizedStringKey {
            switch self {
            case .share: "Share"
            case .windows: "Windows"
            case .notes: "Notes"
            }
        }
    }

    var body: some View {
        HmmPanel("Actions", width: 340, sizing: HmmPanelSizing(id: "actions"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if let page {
                    Button {
                        HmmHaptics.play(.selection)
                        self.page = nil
                    } label: {
                        Label(page.title, systemImage: "chevron.backward").font(.hmm(.headline, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("actions-back")
                    switch page {
                    case .share: share
                    case .windows: windows
                    case .notes: notes
                    }
                } else {
                    TileGrid {
                        TileButton(title: "Share", systemName: "square.and.arrow.up", identifier: "actions-share") { page = .share }
                        TileButton(title: "Windows", systemName: "macwindow.on.rectangle", identifier: "actions-windows") { page = .windows }
                        TileButton(title: "Notes", systemName: "mappin.and.ellipse", identifier: "actions-notes") { page = .notes }
                        TileButton(title: "History", systemName: "clock.arrow.circlepath", identifier: "open-history") { editor.openHistory() }
                        TileButton(title: "Learn", systemName: "graduationcap", identifier: "open-learn") { open(.learn) }
                        TileButton(title: "Settings", systemName: "gearshape") { open(.settings) }
                    }
                }
            }
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
    }

    /// Export, the project file, a USDZ for AR Quick Look, Present.
    private var share: some View {
        TileGrid {
            TileButton(title: "Export", systemName: "square.and.arrow.up", identifier: "open-export") { open(.export) }
            TileButton(title: "Project file", systemName: "doc.zipper") { shareProject() }
            TileButton(title: "Share for AR", systemName: "cube.transparent", identifier: "share-ar") { editor.shareForAR() }
            TileButton(title: "Present", systemName: "play.tv", identifier: "present") {
                editor.openPanel = nil
                editor.startPresenting()
            }
        }
    }

    /// What opens beside or over the stage: the Reference window, the Monitor, the Rotoscope, the AR view, the Board
    /// and the iPhone (while they're held, only outside the App Store build).
    private var windows: some View {
        TileGrid {
            // Q1: the window over the stage (Canvas, Image, Face); its picture comes in from the window itself.
            TileButton(title: "Reference", systemName: "photo.on.rectangle.angled", identifier: "open-reference", isOn: editor.referenceOpen) {
                editor.openPanel = nil
                editor.toggleReferenceWindow()
            }
            // The shot in its own window: beside the editor in Stage Manager, or on an external display.
            TileButton(title: "Monitor", systemName: "rectangle.on.rectangle", identifier: "open-monitor") {
                openWindow(id: LoweyWindow.monitor)
            }
            RotoscopeTile(editor: editor)
            // M12: the scene in the room, drawn in its Look.
            if editor.canShowAR {
                TileButton(title: "View in AR", systemName: "arkit", identifier: "open-ar") { editor.openAR() }
            }
            if boardEnabled, Held.isOn(.board) {
                TileButton(title: "Board", systemName: "scribble.variable", identifier: "open-board") { editor.openBoard() }
            }
            if Held.isOn(.companion) {
                TileButton(title: "Your iPhone", systemName: "iphone", identifier: "open-phone") { open(.phone) }
            }
        }
    }

    /// U8: notes on their spots, a new one, clearing the resolved, a review over FaceTime (held).
    private var notes: some View {
        TileGrid {
            TileButton(title: "Show notes", systemName: "mappin.and.ellipse", identifier: "open-notes", isOn: editor.together.notesShown) {
                editor.setNotesShown(!editor.together.notesShown)
            }
            TileButton(title: "Add a note", systemName: "plus.bubble", identifier: "add-note") { editor.beginNote() }
            if editor.together.notesShown, editor.baseScene.notes.contains(where: \.resolved) {
                TileButton(title: "Clear resolved", systemName: "checkmark.bubble", identifier: "clear-resolved") {
                    editor.clearResolvedNotes()
                }
            }
            if Held.isOn(.faceTimeReview), app.review.call.isOn, !editor.together.reviewing {
                TileButton(title: "Review over FaceTime", systemName: "shareplay", identifier: "start-review") {
                    editor.openPanel = nil
                    app.startReview()
                }
            }
        }
    }

    private func open(_ sheet: EditorSheet) {
        editor.openPanel = nil
        editor.sheet = sheet
    }

    private func shareProject() {
        guard let project = app.projects.first(where: { $0.url == editor.projectURL }) else { return }
        Task {
            await editor.saveNow(thumbnail: false)
            sharing = app.package(project)
        }
    }
}
