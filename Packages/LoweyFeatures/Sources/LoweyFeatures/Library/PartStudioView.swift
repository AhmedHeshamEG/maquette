import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The Part Studio (L2, D-484), in the Studio grammar: the part's picture at the top, then what it is (its job on a
/// character decides where it goes and how the rig moves it) and About. Its shape is changed on the stage, as any
/// thing's is: put it on a character, change it there, and save it to Yours again.
struct PartStudioView: View {
    let editor: EditorModel
    let id: String
    @State private var page: PartStudioPage = .part
    @State private var sharing: IdentifiedURL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    private var part: SavedPart? { editor.library.manifest.part(id) }

    var body: some View {
        if let part {
            HmmStudio(part.name, page: $page, identifier: "part-studio", previewHeight: 200) {
                ZStack {
                    theme.surface2
                    if let picture = editor.library.partThumbnail(part.id) {
                        Image(uiImage: picture).resizable().scaledToFit()
                    } else {
                        Image(systemName: "puzzlepiece").font(.system(size: 44)).foregroundStyle(theme.text3)
                    }
                }
                .accessibilityLabel(Text("The part \(part.name)"))
            } content: { page in
                VStack(alignment: .leading, spacing: HmmSpacing.s) {
                    switch page {
                    case .part:
                        Picker("It's a character's", selection: Binding(get: { part.job }, set: { job in change { $0.job = job } })) {
                            ForEach(CharacterPart.Job.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("part-studio-job")
                        Hint("Face parts, ears, hair and extras go on the head; the rest on the body. The rig moves it as that part.")
                    case .about:
                        HmmStudioAbout(name: Binding(get: { part.name }, set: { value in change { $0.name = value } }),
                                       origin: editor.library.origin(.part, part.id),
                                       note: "Change its shape on a character, then save it to Yours again from its menu.")
                    }
                }
                .font(.hmm(.body))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Share as a pack", systemImage: "square.and.arrow.up") {
                        sharing = editor.app.writePack([.part(id)], name: part.name, author: editor.app.packAuthor,
                                                       licence: editor.app.packLicence).map(IdentifiedURL.init)
                    }
                    Button("Put it on") {
                        editor.addSavedPart(part)
                        dismiss()
                    }
                    .accessibilityIdentifier("part-studio-use")
                }
            }
            .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        }
    }

    private func change(_ edit: (inout SavedPart) -> Void) {
        guard var edited = part else { return }
        edit(&edited)
        editor.library.updatePart(edited)
    }
}

enum PartStudioPage: String, CaseIterable, HmmStudioPage {
    case part, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .part: "Part"
        case .about: "About"
        }
    }
}
