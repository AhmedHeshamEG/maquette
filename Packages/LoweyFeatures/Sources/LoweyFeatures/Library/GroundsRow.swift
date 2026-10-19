import HmmDesign
import LoweyCore
import SwiftUI

/// Library ▸ Things ▸ Grounds (L2, D-489): what the world stands on. One tap makes the floor desert, grass, snow, rock,
/// sand, pavement, a water's edge or a room's boards; Plain goes back to a floor in its colour. One undo step each.
struct GroundsRow: View {
    let editor: EditorModel

    private var current: GroundSurface? { editor.look.ground.visible ? editor.look.ground.surface : nil }

    var body: some View {
        PanelSection("Grounds") {
            TileGrid {
                TileButton(title: "Plain", systemName: "square", identifier: "ground-plain", isOn: current == nil) { editor.setGround(nil) }
                ForEach(GroundSurface.allCases) { surface in
                    TileButton(title: surface.title, systemName: surface.systemImage, identifier: "ground-\(surface.rawValue)",
                               isOn: current == surface) {
                        editor.setGround(surface)
                    }
                }
            }
            Hint("The whole world's floor. Its colour is in Look ▸ World.")
        }
    }
}
