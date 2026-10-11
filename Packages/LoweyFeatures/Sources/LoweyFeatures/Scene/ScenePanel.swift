import HmmDesign
import LoweyCore
import SwiftUI

/// The scene's name is a door (top left, under the clusters): what the project is set up for, its scenes, and the
/// objects in this one.
struct ScenePanel: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var renamingScene = false
    @State private var sceneName = ""

    var body: some View {
        HmmPanel(editor.baseScene.name, width: 360, sizing: HmmPanelSizing(id: "scene"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                setUp
                scenes
                SceneObjectsSection(editor: editor)
            }
        }
        .alert("Rename scene", isPresented: $renamingScene) {
            TextField("Name", text: $sceneName)
            Button("Rename") { editor.renameScene(sceneName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// "Set up for": switchable at any time; it changes what is in reach, never what was made.
    private var setUp: some View {
        PanelSection("Set up for") {
            TileGrid(minimum: 96) {
                ForEach(StarterTemplate.setUps, id: \.self) { kind in
                    TileButton(title: kind.title, systemName: kind.systemImage, identifier: "setup-\(kind.rawValue)",
                               isOn: editor.projectSetUp == kind) { editor.setUp(for: kind) }
                }
            }
            Hint("Units, snapping, the grid and the timeline follow the job. What you made stays as it is.")
        }
    }

    private var scenes: some View {
        PanelSection("Scenes") {
            ForEach(editor.sceneList, id: \.id) { item in
                Button {
                    editor.switchScene(item.id)
                } label: {
                    HStack {
                        Text(item.name).font(.hmm(.body, weight: item.id == editor.baseScene.id ? .semibold : .regular)).lineLimit(2)
                        Spacer()
                        if item.id == editor.baseScene.id { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("New", systemName: "plus") { editor.addScene() }
                    .accessibilityIdentifier("scene-new")
                HmmPillButton("Duplicate", systemName: "plus.square.on.square") { editor.duplicateScene() }
                HmmPillButton("Rename", systemName: "pencil") {
                    sceneName = editor.baseScene.name
                    renamingScene = true
                }
                .accessibilityIdentifier("scene-rename")
            }
            let others = app.projects.filter { $0.url != editor.projectURL }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { project in
                        Button(project.info.name) {
                            Task {
                                await editor.saveNow(thumbnail: false)
                                app.copyScene(editor.baseScene.id, from: editor.projectURL, to: project)
                            }
                        }
                    }
                } label: {
                    Label("Copy this scene to…", systemImage: "doc.on.doc").font(.hmm(.body, weight: .semibold))
                }
            }
        }
    }
}
