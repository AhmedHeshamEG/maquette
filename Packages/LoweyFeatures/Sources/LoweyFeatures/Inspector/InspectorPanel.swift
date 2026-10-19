import HmmDesign
import LoweyCore
import SwiftUI

/// The object panel (CONTEXT §10.10): one screen beside the selection. Move · Turn · Size, its colour, what kind of
/// thing it is, Make it move; one step deeper, Look of this object, More ways to move, the numbers and what it is.
/// Its header is a grip: drag it anywhere and it stays there; the fold button (or opening something big) folds it to
/// a chip. The ⋯ button is the object's one menu, the same as touching and holding it.
struct InspectorPanel: View {
    @Bindable var editor: EditorModel
    @Binding var size: HmmPanelSize?
    /// The header's drag (the Shell moves the panel and remembers where it was left).
    var move: InspectorMove?
    static let sizing = HmmPanelSizing(id: "inspector", minimum: CGSize(width: 290, height: 240), maximum: CGSize(width: 520, height: 1400))
    static let defaultSize = CGSize(width: 330, height: 560)
    @State private var name = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, HmmSpacing.m)
                .padding(.top, HmmSpacing.s)
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.m) {
                    // A model that just came in is offered a rig, once (CONTEXT §10.8).
                    if let object = editor.singleSelection, editor.rigItOffer == object.id {
                        HmmPillButton("Rig it", systemName: "figure.stand", prominent: true) { editor.takeRigItOffer() }
                            .accessibilityIdentifier("rig-it")
                    }
                    GizmoModeRow(editor: editor)
                    SizeSection(editor: editor)
                    if let object = editor.singleSelection {
                        single(object)
                    } else {
                        several
                    }
                    actions
                }
                .padding(HmmSpacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .hmmResizable(Self.sizing, size: $size, defaultWidth: Self.defaultSize.width, title: "Inspector", appliesFrame: false)
        .hmmPanelBackground()
        .onAppear { name = editor.singleSelection?.name ?? "" }
        .onChange(of: editor.selection) { _, _ in
            name = editor.singleSelection?.name ?? ""
            if editor.rigItOffer != editor.singleSelection?.id { editor.rigItOffer = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }

    @ViewBuilder
    private func single(_ object: SceneObject) -> some View {
        if object.kind.hasSurface { ColourRow(editor: editor, object: object) }
        KindSection(editor: editor, object: object)
        // A made character's parts and face, or "Give it parts" for any thing (K1).
        CharacterSection(editor: editor, object: object)
        MakeItMove(editor: editor)
        SelectionActions(editor: editor)
        VStack(alignment: .leading, spacing: 0) {
            if object.kind.hasSurface || object.kind == .group {
                DisclosureRow("Look of this object", systemName: "paintpalette", identifier: "object-look") {
                    ObjectLookSection(editor: editor, object: object)
                }
            }
            if object.kind.hasSurface {
                DisclosureRow("Shape of this object", systemName: "cube.transparent", identifier: "object-shape") {
                    ShapeSection(editor: editor, object: object)
                }
            }
            if object.kind.hasSurface || object.kind == .group {
                DisclosureRow(object.physics == nil ? "Real" : "Real: \(object.physics?.material.title ?? "")", systemName: "atom", identifier: "object-real") {
                    RealSection(editor: editor, object: object)
                }
            }
            if let clones = object.motionDesign?.clones {
                DisclosureRow("Clones: \(clones.count)", systemName: "square.grid.3x3.square", identifier: "object-clones") {
                    CloneSection(editor: editor, object: object, clones: clones)
                }
            }
            if let morph = object.motionDesign?.morph {
                DisclosureRow("Morph", systemName: "wand.and.rays", identifier: "object-morph") {
                    MorphRow(editor: editor, object: object, morph: morph)
                }
            }
            DisclosureRow("More ways to move", systemName: "figure.run", identifier: "more-motion") {
                MoreWaysToMove(editor: editor)
            }
            DisclosureRow("Numbers", systemName: "number", identifier: "transform-toggle") {
                TransformSection(editor: editor, object: object)
            }
            DisclosureRow("About this object", systemName: "info.circle", identifier: "inspector-more") {
                MetadataSection(editor: editor, object: object)
            }
        }
    }

    @ViewBuilder private var several: some View {
        Text("\(editor.selection.count) objects").font(.hmm(.body)).foregroundStyle(theme.text2)
        PaletteRow(palette: editor.look.palette, selected: nil) { editor.setColor(.palette($0)) }
        MakeItMove(editor: editor)
        SelectionActions(editor: editor)
        ArrangeSection(editor: editor)
        VStack(alignment: .leading, spacing: 0) {
            DisclosureRow("Look of these objects", systemName: "paintpalette", identifier: "object-look") {
                LookOverrideSection(editor: editor, object: nil)
            }
            DisclosureRow("Real", systemName: "atom", identifier: "object-real") {
                RealSeveral(editor: editor)
            }
            DisclosureRow("More ways to move", systemName: "figure.run", identifier: "more-motion") {
                MoreWaysToMove(editor: editor)
            }
        }
    }

    private var header: some View {
        HStack(spacing: HmmSpacing.s) {
            if let object = editor.singleSelection {
                Image(systemName: Self.icon(for: object.kind)).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
                TextField("Name", text: $name)
                    .font(.hmm(.headline, weight: .semibold))
                    .onSubmit { editor.rename(object.id, to: name) }
                    .accessibilityIdentifier("inspector-name")
                if object.kind.prefabID != nil { Badge(text: "BUILD") }
            } else {
                Text("Selection").font(.hmm(.headline, weight: .semibold))
            }
            Spacer()
            HmmButton("rectangle.compress.vertical", label: "Fold the panel", size: 32) { editor.foldInspector(true) }
                .accessibilityIdentifier("fold-inspector")
            HmmButton("xmark", label: "Deselect", size: 32) { editor.setSelection([]) }
        }
        .padding(.top, HmmSpacing.xxs)
        .overlay(alignment: .top) {
            if move != nil { Capsule().fill(theme.text3).frame(width: 36, height: 4).offset(y: -6).allowsHitTesting(false) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { move?.changed($0.translation) }
                .onEnded { _ in move?.ended() }
        )
        .onTapGesture(count: 2) { move?.reset() }
    }

    /// Duplicate and Hide as buttons, the object's one menu, Delete.
    private var actions: some View {
        let object = editor.singleSelection
        return HStack(spacing: HmmSpacing.xs) {
            HmmButton("plus.square.on.square", label: "Duplicate", size: 40) { editor.duplicateSelection() }
            if let object {
                HmmButton(object.isVisible ? "eye.slash" : "eye", label: object.isVisible ? "Hide" : "Show", size: 40) { editor.toggleVisible(object.id) }
            }
            Menu {
                HmmHoldMenuContent(editor.holdMenu(for: editor.selection))
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 40)
            }
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("more-actions")
            Spacer(minLength: 0)
            HmmButton("trash", label: "Delete", size: 40, role: .destructive) { editor.deleteSelection() }
        }
    }

    static func icon(for kind: ObjectKind) -> String {
        kind.symbolName
    }
}

/// How the Shell moves the panel by its header.
struct InspectorMove {
    let changed: (CGSize) -> Void
    let ended: () -> Void
    /// Double-tap: back beside the selection.
    let reset: () -> Void
}

/// The folded panel: the thing's name (tap to unfold) and Move · Turn · Size.
struct InspectorChip: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            Button {
                HmmHaptics.play(.selection)
                editor.foldInspector(false)
            } label: {
                HStack(spacing: HmmSpacing.xxs) {
                    if let object = editor.singleSelection {
                        Image(systemName: InspectorPanel.icon(for: object.kind)).foregroundStyle(theme.accent)
                        Text(verbatim: object.name).lineLimit(1)
                    } else {
                        Text("\(editor.selection.count) objects").lineLimit(1)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.text3)
                }
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, HmmSpacing.s)
                .frame(minHeight: 40)
                .frame(maxWidth: 180, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Unfold the panel")
            .accessibilityIdentifier("unfold-inspector")
            GizmoModeRow(editor: editor, compact: true)
        }
        .padding(HmmSpacing.xxs)
        .hmmPanelBackground(cornerRadius: HmmRadius.card + 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector-chip")
    }
}
