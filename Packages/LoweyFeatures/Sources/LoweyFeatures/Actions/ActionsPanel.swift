import HmmDesign
import LoweyCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Actions: making and sharing. Export and the project file, the Monitor window, the Board, the Reference window,
/// History; Learn and Settings. (The scenes are behind the scene's name; the assistant and scripts are in Settings ▸ Assistant; sound
/// and the timeline's settings live in the timeline.)
struct ActionsPanel: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var sharing: URL?
    @AppStorage(AppSettings.boardEnabled) private var boardEnabled = true
    @Environment(\.openWindow) private var openWindow
    @State private var choosingReference = false
    @State private var reference: PhotosPickerItem?

    var body: some View {
        HmmPanel("Actions", width: 340, sizing: HmmPanelSizing(id: "actions"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                PanelSection("Share") {
                    TileGrid {
                        TileButton(title: "Export", systemName: "square.and.arrow.up", identifier: "open-export") { open(.export) }
                        TileButton(title: "Project file", systemName: "doc.zipper") { shareProject() }
                        // The shot in its own window: beside the editor in Stage Manager, or on an external display.
                        TileButton(title: "Monitor", systemName: "rectangle.on.rectangle", identifier: "open-monitor") {
                            openWindow(id: LoweyWindow.monitor)
                        }
                    }
                }
                PanelSection("Project") {
                    TileGrid {
                        if boardEnabled {
                            TileButton(title: "Board", systemName: "scribble.variable", identifier: "open-board") { editor.openBoard() }
                        }
                        TileButton(title: "Reference", systemName: "photo.on.rectangle.angled", identifier: "open-reference") {
                            choosingReference = true
                        }
                        if UIPasteboard.general.hasImages {
                            TileButton(title: "Paste a reference", systemName: "doc.on.clipboard", identifier: "paste-reference") {
                                editor.openPanel = nil
                                editor.pasteReference()
                            }
                        }
                        TileButton(title: "History", systemName: "clock.arrow.circlepath", identifier: "open-history") { editor.openHistory() }
                    }
                }
                PanelSection("Help") {
                    TileGrid {
                        TileButton(title: "Learn", systemName: "graduationcap", identifier: "open-learn") { open(.learn) }
                        TileButton(title: "Settings", systemName: "gearshape") { open(.settings) }
                    }
                }
            }
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
        .photosPicker(isPresented: $choosingReference, selection: $reference, matching: .images)
        .onChange(of: reference) { _, item in
            guard let item else { return }
            reference = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                editor.openPanel = nil
                editor.addReference(imageData: data)
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
