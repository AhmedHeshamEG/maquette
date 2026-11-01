import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Model ▸ Add in groups (U9): Shapes · Lights · Words & pictures · Effects, and the set-up's kit as a fifth in a Room,
/// Print or Game project (open first there; Shapes first everywhere else). One tap each; things land in the
/// middle of the view, and the panel closes so the panel of what was added shows (as Procreate Dreams' insert menu
/// does). The set-up's kit is here too (G1): Room's building tools and plans, Print's pieces, Game's greybox. Cameras live
/// on the camera button; titles, marks and screen effects are overlays on the video, in the timeline's + Overlay.
struct ModelAddPage: View {
    let editor: EditorModel
    @State private var importingMedia = false
    @State private var importingLogo = false
    @State private var importingDrawing = false
    @State private var importingWeb = false
    @State private var webFile: URL?
    @State private var group: AddGroup?

    /// The set-up's kit when the project has one that shows (Room, Print while threads ship, Game).
    private var hasKit: Bool {
        switch editor.projectSetUp {
        case .room, .game: true
        case .print: Held.isOn(.threads)
        default: false
        }
    }

    private var groups: [AddGroup] { (hasKit ? [AddGroup.kit] : []) + [.shapes, .lights, .words, .effects] }

    var body: some View {
        let shown = group.flatMap { groups.contains($0) ? $0 : nil } ?? groups[0]
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            AddGroupBar(groups: groups, selected: shown) { group = $0 }
            switch shown {
            case .kit: GuestAddSections(editor: editor)
            case .shapes: shapes
            case .lights: lights
            case .words: words
            case .effects: effects
            }
        }
        .fileImporter(isPresented: $importingMedia, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                Task { await editor.importMedia(url) }
            }
        }
        .fileImporter(isPresented: $importingWeb, allowedContentTypes: EditorModel.webTypes) { result in
            if case let .success(url) = result { webFile = url }
        }
        .confirmationDialog("Where does it play?", isPresented: Binding(get: { webFile != nil }, set: { if !$0 { webFile = nil } }),
                            titleVisibility: .visible) {
            Button("On a screen in the scene") { addWeb(.card) }
            Button("Over the frame") { addWeb(.overlay) }
        }
        .fileImporter(isPresented: $importingLogo, allowedContentTypes: [.svg]) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                editor.importLogo(url)
            }
        }
        .fileImporter(isPresented: $importingDrawing, allowedContentTypes: EditorModel.drawingTypes) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                Task { await editor.importDrawing(url) }
            }
        }
    }

    private var shapes: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Shapes") {
                TileGrid {
                    ForEach(PrimitiveShape.allCases, id: \.self) { shape in
                        TileButton(title: shape.displayName, systemName: Self.icon(for: shape), identifier: "add-\(shape.rawValue)",
                                   glyph: shape == .sphere ? AnyView(SphereGlyph()) : nil) {
                            place { editor.addPrimitive(shape) }
                        }
                    }
                }
            }
        }
    }

    private var lights: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Lights") {
                TileGrid {
                    TileButton(title: "Bulb", systemName: "lightbulb.fill", identifier: "add-lamp") { place { editor.addLight(.point) } }
                    TileButton(title: "Spot", systemName: "light.overhead.right.fill", identifier: "add-spot") { place { editor.addLight(.spot) } }
                    TileButton(title: "Soft panel", systemName: "light.panel.fill", identifier: "add-panel") { place { editor.addLight(.area) } }
                    TileButton(title: "Sun", systemName: "sun.max.fill", identifier: "add-sun") { place { editor.addLight(.directional) } }
                }
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Words & pictures") {
                TileGrid {
                    TileButton(title: "3D text", systemName: "textformat", identifier: "add-text3d") { place { editor.addText3D() } }
                    TileButton(title: "Photo or video", systemName: "photo.on.rectangle", identifier: "add-media") { importingMedia = true }
                    TileButton(title: "Logo (SVG)", systemName: "seal", identifier: "add-logo") { importingLogo = true }
                    TileButton(title: "Drawing (PSD, Procreate)", systemName: "square.3.layers.3d", identifier: "add-drawing") {
                        importingDrawing = true
                    }
                    if Held.isOn(.webPieces) {
                        TileButton(title: "Web page or Lottie", systemName: "globe", identifier: "add-web") { importingWeb = true }
                    }
                }
            }
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Effects") {
                TileGrid {
                    ForEach(ParticleRecipe.Preset.allCases) { preset in
                        TileButton(title: preset.title, systemName: preset.systemImage, identifier: "add-fx-\(preset.rawValue)") {
                            place { editor.addParticles(preset) }
                        }
                    }
                }
            }
            PanelSection("Forces & fluids") {
                TileGrid {
                    ForEach(ForceRecipe.Kind.allCases, id: \.self) { kind in
                        TileButton(title: kind.title, systemName: kind.systemImage, identifier: "add-force-\(kind.rawValue)") {
                            place { editor.addForce(kind) }
                        }
                    }
                    ForEach(FluidRecipe.Kind.allCases, id: \.self) { kind in
                        TileButton(title: Self.fluidTitle(kind), systemName: kind.systemImage, identifier: "add-fluid-\(kind.rawValue)") {
                            place { editor.addFluid(kind) }
                        }
                    }
                }
                Hint("Fans and pulls push real things; water, smoke and fire fill a room-sized box around them.")
            }
        }
    }

    private func addWeb(_ placement: MediaPlacement) {
        guard let url = webFile else { return }
        webFile = nil
        editor.openPanel = nil
        Task { await editor.importMedia(url, as: placement) }
    }

    private func place(_ add: () -> Void) {
        add()
        editor.openPanel = nil
    }

    /// Water and flames say what they are, so they don't read as the particle Smoke and Fire above them.
    static func fluidTitle(_ kind: FluidRecipe.Kind) -> String {
        switch kind {
        case .pour: String(localized: "Pour water")
        case .splash: String(localized: "Splash")
        case .smoke: String(localized: "Billowing smoke")
        case .fire: String(localized: "Flames")
        }
    }

    static func icon(for shape: PrimitiveShape) -> String {
        switch shape {
        case .cube: "cube.fill"
        case .sphere: "circle.fill"
        case .cylinder: "cylinder.fill"
        case .cone: "cone.fill"
        case .plane: "square.fill"
        case .torus: "circle.circle"
        case .ramp: "triangle.fill"
        }
    }
}

/// Model ▸ Add's groups (U9).
enum AddGroup: String, CaseIterable, Identifiable {
    case kit, shapes, lights, words, effects

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .kit: "Kit"
        case .shapes: "Shapes"
        case .lights: "Lights"
        case .words: "Words & pictures"
        case .effects: "Effects"
        }
    }

    var symbol: String {
        switch self {
        case .kit: "shippingbox"
        case .shapes: "cube"
        case .lights: "lightbulb"
        case .words: "textformat"
        case .effects: "sparkles"
        }
    }
}

/// The row of groups: one tap shows a group's tiles.
struct AddGroupBar: View {
    let groups: [AddGroup]
    let selected: AddGroup
    let choose: (AddGroup) -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            ForEach(groups) { group in
                Button {
                    HmmHaptics.play(.selection)
                    choose(group)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: group.symbol).font(.system(size: 15, weight: .semibold))
                        Text(group.title).font(.hmm(.caption, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(group == selected ? theme.accent : theme.text2)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: HmmRadius.card).fill(group == selected ? theme.accent.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(group == selected ? .isSelected : [])
                .accessibilityIdentifier("add-group-\(group.rawValue)")
            }
        }
    }
}
