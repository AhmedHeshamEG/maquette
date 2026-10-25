import HmmDesign
import LoweyCore
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
                // U8: show it on a screen, leave notes on it, review it over FaceTime, hand it to the iPhone.
                PanelSection("Show and review") {
                    TileGrid {
                        TileButton(title: "Present", systemName: "play.tv", identifier: "present") {
                            editor.openPanel = nil
                            editor.startPresenting()
                        }
                        TileButton(title: "Notes", systemName: "mappin.and.ellipse", identifier: "open-notes", isOn: editor.together.notesShown) {
                            editor.setNotesShown(!editor.together.notesShown)
                        }
                        TileButton(title: "Add a note", systemName: "plus.bubble", identifier: "add-note") { editor.beginNote() }
                        if editor.together.notesShown, editor.baseScene.notes.contains(where: \.resolved) {
                            TileButton(title: "Clear resolved", systemName: "checkmark.bubble", identifier: "clear-resolved") {
                                editor.clearResolvedNotes()
                            }
                        }
                        if app.review.call.isOn, !editor.together.reviewing {
                            TileButton(title: "Review over FaceTime", systemName: "shareplay", identifier: "start-review") {
                                editor.openPanel = nil
                                app.startReview()
                            }
                        }
                        TileButton(title: "Your iPhone", systemName: "iphone", identifier: "open-phone") { open(.phone) }
                    }
                }
                PanelSection("Project") {
                    TileGrid {
                        if boardEnabled {
                            TileButton(title: "Board", systemName: "scribble.variable", identifier: "open-board") { editor.openBoard() }
                        }
                        // Q1: the window over the stage (Canvas, Image, Face); its picture comes in from the window itself.
                        TileButton(title: "Reference", systemName: "photo.on.rectangle.angled", identifier: "open-reference",
                                   isOn: editor.referenceOpen) {
                            editor.openPanel = nil
                            editor.toggleReferenceWindow()
                        }
                        RotoscopeTile(editor: editor)
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
