import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Model ▸ Add: shapes (bevelled), lights, words and pictures in the world, effects. One tap each; things land in the
/// middle of the view, and the panel closes so the panel of what was added shows (as Procreate Dreams' insert menu
/// does). Building (walls, floors, doors, windows, stairs) is here while the project is set up for a Room. Cameras live
/// on the camera button; titles, marks and screen effects are overlays on the video, in the timeline's + Overlay.
struct ModelAddPage: View {
    let editor: EditorModel
    @State private var importingMedia = false

    var body: some View {
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
            if editor.projectSetUp == .room {
                PanelSection("Building") {
                    TileGrid {
                        ForEach(BuildTool.allCases) { build in
                            TileButton(title: build.title, systemName: build.systemImage, identifier: "build-\(build.rawValue)") {
                                editor.startModeling(.build(build))
                                editor.openPanel = nil
                            }
                        }
                    }
                    Hint("Walls follow the corners you tap; doors and windows go where you tap a wall.")
                }
            }
            PanelSection("Light") {
                TileGrid {
                    TileButton(title: "Bulb", systemName: "lightbulb.fill", identifier: "add-lamp") { place { editor.addLight(.point) } }
                    TileButton(title: "Spot", systemName: "light.overhead.right.fill", identifier: "add-spot") { place { editor.addLight(.spot) } }
                    TileButton(title: "Soft panel", systemName: "light.panel.fill", identifier: "add-panel") { place { editor.addLight(.area) } }
                    TileButton(title: "Sun", systemName: "sun.max.fill", identifier: "add-sun") { place { editor.addLight(.directional) } }
                }
            }
            PanelSection("Words & pictures") {
                TileGrid {
                    TileButton(title: "3D text", systemName: "textformat", identifier: "add-text3d") { place { editor.addText3D() } }
                    TileButton(title: "Photo or video", systemName: "photo.on.rectangle", identifier: "add-media") { importingMedia = true }
                }
            }
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
        .fileImporter(isPresented: $importingMedia, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                Task { await editor.importMedia(url) }
            }
        }
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
