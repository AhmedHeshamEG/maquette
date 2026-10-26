import Foundation
import HmmWeb
import LoweyCore

extension ModelExport {
    /// Export ▸ 3D ▸ three.js (X1): the scene as a folder for the web, in one zip, carrying the kit's own three.js.
    static func webFolder(_ glb: Data, scene: CoreScene, look: Look, preset: LookPreset, name: String) -> [(name: String, data: Data)] {
        let three = HmmWebPage.libraryFolder?.appendingPathComponent("three", isDirectory: true)
        let input = ThreeProject.Input(scene: scene, look: look, preset: preset, glb: glb, name: name) { path in
            three.flatMap { try? Data(contentsOf: $0.appendingPathComponent(path)) }
        }
        guard let archive = try? ThreeProject.archive(input) else { return [] }
        return [archive]
    }
}
