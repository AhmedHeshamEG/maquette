import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// Share a pack (L2, D-485): tick what goes in from Yours (Looks, brushes, materials, effects, parts, motions, things),
/// name it, say who made it and what others may do with it, and share the one `.maquettepack` file anywhere. Things
/// that came from someone else's pack keep their author whatever is chosen here.
struct PackSheet: View {
    let editor: EditorModel
    @State private var chosen: Set<PackChoice> = []
    @State private var name = ""
    @State private var author = ""
    @State private var licence = HmmLicence.anything
    @State private var sharing: IdentifiedURL?
    @Environment(\.dismiss) private var dismiss

    private var app: AppModel { editor.app }
    private var manifest: LibraryManifest { editor.library.manifest }

    private var looks: [LookPreset] {
        manifest.styles + editor.document.project.customLooks.filter { mine in !manifest.styles.contains { $0.id == mine.id } }
    }

    var body: some View {
        Form {
            Section {
                HmmPackForm(name: $name, author: $author, licence: $licence, count: chosen.count)
            }
            group("Looks", looks.map { PackRow(choice: .look($0.id), name: $0.name) })
            group("Brushes", app.brushes.library.allBrushes.filter { !app.brushes.library.isBuiltIn($0.id) }
                .map { PackRow(choice: .brush($0.id), name: $0.name) })
            group("Materials", app.materials.library.own.map { PackRow(choice: .material($0.id), name: $0.name) })
            group("Effects", manifest.effects.map { PackRow(choice: .effect($0.id), name: $0.name) })
            group("Parts", manifest.parts.map { PackRow(choice: .part($0.id), name: $0.name) })
            group("Motion", manifest.motions.map { PackRow(choice: .motion($0.id), name: $0.name) })
            group("Things", manifest.prefabs.map { PackRow(choice: .thing($0.id), name: $0.name) })
        }
        .navigationTitle("Share a pack")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    sharing = app.writePack(Array(chosen), name: name, author: author, licence: licence, looks: editor.document.project.customLooks)
                        .map(IdentifiedURL.init)
                }
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("pack-share")
            }
        }
        .sheet(item: $sharing, onDismiss: { dismiss() }) { ShareSheet(items: [$0.url]) }
        .onAppear {
            author = app.packAuthor
            licence = app.packLicence
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [PackRow]) -> some View {
        if !items.isEmpty {
            Section(LocalizedStringKey(title)) {
                ForEach(items) { item in
                    Button {
                        if chosen.contains(item.choice) {
                            chosen.remove(item.choice)
                        } else {
                            chosen.insert(item.choice)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: item.name)
                            Spacer()
                            if chosen.contains(item.choice) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(item.choice) ? .isSelected : [])
                }
            }
        }
    }
}

/// One thing that can go in a pack, as the sheet lists it.
struct PackRow: Identifiable {
    let choice: PackChoice
    let name: String
    var id: PackChoice { choice }
}
