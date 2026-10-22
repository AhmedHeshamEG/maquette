import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// Home, the living gallery (CONTEXT §4.2): Procreate's grid where each card is the real model turning in its own
/// light. Tap a card and it grows into the stage. Stacks keep projects together (drag one card onto another), search
/// finds them anywhere, the sort is remembered, and Select acts on several at once.
struct TheaterView: View {
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var app
    @State private var state = GalleryState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.xl) {
                TheaterHeader(state: state)
                if state.query.isEmpty, !state.selecting { SetUpRow(stack: state.openStack) }
                grid
            }
            .padding(HmmSpacing.xl)
        }
        .onScrollPhaseChange { _, phase in state.scrolling = phase.isScrolling }
        .safeAreaInset(edge: .bottom) {
            if state.selecting { GallerySelectionBar(state: state).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .hmmAnimation(.standard, value: state.selecting)
        .modifier(TheaterDialogs(state: state))
        .accessibilityIdentifier("home")
    }

    private var entries: [GalleryEntry] {
        app.gallery.entries(app.galleryItems, in: state.openStack, query: state.query)
    }

    /// Cards play only while the gallery rests and no project is open over it.
    private var playing: Bool { !state.scrolling && app.editor == nil }

    @ViewBuilder private var grid: some View {
        let entries = entries
        if entries.isEmpty, !state.query.isEmpty {
            HmmEmptyState("questionmark.folder", title: "Nothing called “\(state.query)”",
                          message: "Search looks through every project and stack by name.", actionTitle: "Clear the search") { state.query = "" }
        } else {
            GalleryGrid(entries: entries, zoom: zoom, playing: playing, selected: state.selecting ? state.selected : nil,
                        newProject: state.query.isEmpty && !state.selecting ? { app.startProject(inStack: state.openStack) } : nil,
                        open: tap,
                        openStack: { stack in
                            withHmmAnimation(.gentle) {
                                state.query = ""
                                state.openStack = stack.id
                            }
                        },
                        drop: { id, entry in withHmmAnimation(.standard) { app.drop(id, onto: entry) } },
                        rename: { project in
                            state.nameText = project.info.name
                            state.renaming = project
                        },
                        samples: state.openStack == nil && state.query.isEmpty && !state.selecting ? AnyView(SamplesCard(playing: playing)) : nil,
                        projectMenu: { ProjectMenu(project: $0, state: state) },
                        stackMenu: { StackMenu(stack: $0, state: state) })
        }
    }

    private func tap(_ project: ProjectSummary) {
        if state.selecting {
            HmmHaptics.play(.selection)
            state.selected.formSymmetricDifference([project.id.raw])
        } else {
            app.open(url: project.url)
        }
    }
}

/// Under Home's title, quietly: a new project set up for a job (Blank is the + card).
private struct SetUpRow: View {
    let stack: String?
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        // Five set-ups (G1): on a narrow screen they keep their icons and say their names to VoiceOver.
        ViewThatFits(in: .horizontal) {
            row(iconsOnly: false)
            row(iconsOnly: true)
        }
        .font(.hmm(.footnote, weight: .semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(iconsOnly: Bool) -> some View {
        HStack(spacing: HmmSpacing.m) {
            Text("Or start set up for").foregroundStyle(theme.text3)
            ForEach(StarterTemplate.setUps.filter { $0 != .blank }, id: \.self) { kind in
                Button {
                    HmmHaptics.play(.commit)
                    app.startProject(kind, inStack: stack)
                } label: {
                    if iconsOnly {
                        Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage).labelStyle(.iconOnly)
                    } else {
                        Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text2)
                .accessibilityIdentifier("start-\(kind.rawValue)")
            }
        }
    }
}

/// The samples, once, as one stack-like card: the Keeper's Tower turning on top (L2); tap it for the list, each is
/// made fresh and opened.
private struct SamplesCard: View {
    let playing: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Menu {
            Button("The Keeper's Tower", systemImage: "building.columns") { app.createTowerSample(open: true) }
                .accessibilityIdentifier("sample-tower")
            Button("Welcome island", systemImage: "tree") { app.createIslandSample(open: true) }
                .accessibilityIdentifier("Welcome island")
            Button("The Enigma story", systemImage: "sparkles") { app.createEnigmaSample(open: true) }
        } label: {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                ZStack {
                    ForEach(0 ..< 2) { index in
                        RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous)
                            .fill(theme.surface2.opacity(1 - Double(index) * 0.25))
                            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).stroke(theme.line))
                            .rotationEffect(.degrees(Double(index - 1) * 4))
                            .offset(x: CGFloat(index - 1) * 6)
                    }
                    if let still = app.samplesStill {
                        TurntableView(url: app.samplesLoopURL, still: still, revision: app.samplesRevision, playing: playing)
                            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                            .accessibilityLabel(Text("The Keeper's Tower, turning"))
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 34, weight: .medium)).foregroundStyle(theme.text2)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Samples").font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text)
                    Text("Made in \(AppIdentity.displayName), to open and take apart").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
                .padding(.horizontal, HmmSpacing.xxs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityIdentifier("samples")
    }
}

/// What Home is showing and doing: the open stack, the search, selecting, and the dialogs in flight.
@Observable
@MainActor
final class GalleryState {
    var query = ""
    var openStack: String?
    var selecting = false
    var selected: Set<String> = []
    var scrolling = false
    var showArchive = false
    var importing = false
    var sharing: URL?
    var renaming: ProjectSummary?
    var renamingStack: GalleryStack?
    var naming: [String]?
    var nameText = ""
    var deleting: [String] = []

    func endSelecting() {
        selecting = false
        selected = []
    }
}

/// A project's touch-and-hold menu.
private struct ProjectMenu: View {
    let project: ProjectSummary
    let state: GalleryState
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmHoldMenuContent(menu)
    }

    /// A tap opens a card, so the menu doesn't: its extras are the stack it's in, sharing, and the archive.
    private var menu: HmmHoldMenu {
        let id = project.id.raw
        // Move to… (L2): a stack is a folder, as in the Files app.
        var stacking = [HmmHoldMenu.Item("New stack…", systemName: "plus") {
            state.nameText = ""
            state.naming = [id]
        }]
        stacking += app.gallery.stacks.filter { $0.id != project.folder }.map { stack in
            HmmHoldMenu.Item(stack.name, id: stack.id, isVerbatim: true) { app.addToStack([id], stack: stack.id) }
        }
        if project.folder != nil {
            stacking.append(HmmHoldMenu.Item("Out of the stack", systemName: "arrow.up.square") { app.moveOutOfStacks([id]) })
        }
        let sharing = [
            HmmHoldMenu.Item("Share as one file (.maquettepack)", systemName: "square.and.arrow.up") { state.sharing = app.package(project) },
            HmmHoldMenu.Item("Export folder (with library items)", systemName: "folder") { state.sharing = app.exportFolder(project) }
        ]
        return HmmHoldMenu(duplicate: { app.duplicate(project) }, rename: {
            state.nameText = project.info.name
            state.renaming = project
        }, extras: [
            HmmHoldMenu.Item("Move to…", systemName: "folder", children: stacking),
            HmmHoldMenu.Item("Share", systemName: "square.and.arrow.up", children: sharing),
            HmmHoldMenu.Item("Archive", systemName: "archivebox") { app.archive(project) }
        ], delete: { state.deleting = [id] })
    }
}

/// A stack's touch-and-hold menu.
private struct StackMenu: View {
    let stack: GalleryStack
    let state: GalleryState
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmHoldMenuContent(HmmHoldMenu(rename: {
            state.nameText = stack.name
            state.renamingStack = stack
        }, extras: [
            HmmHoldMenu.Item("Sort inside", systemName: "arrow.up.arrow.down", children: GallerySort.allCases.map { sort in
                HmmHoldMenu.Item(sort.title, id: "sort-\(sort.rawValue)", systemName: app.gallery.sort(in: stack.id) == sort ? "checkmark" : "") {
                    app.setGallerySort(sort, in: stack.id)
                }
            }),
            HmmHoldMenu.Item("Unstack", systemName: "square.stack.3d.down.right") { withHmmAnimation(.standard) { app.unstack(stack.id) } }
        ]))
    }
}
