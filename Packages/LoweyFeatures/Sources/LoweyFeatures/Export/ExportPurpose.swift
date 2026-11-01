import LoweyEngine
import SwiftUI

/// What an export is for (U9): the sheet opens on this, and each picks its formats, the first one the usual answer.
enum ExportPurpose: String, CaseIterable, Identifiable {
    case video, picture, game, print, web, file

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .video: "A video"
        case .picture: "A picture"
        case .game: "Take it to a game"
        case .print: "Print it"
        case .web: "For the web"
        case .file: "A 3D file"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .picture: "photo"
        case .game: "gamecontroller"
        case .print: "printer"
        case .web: "globe"
        case .file: "cube"
        }
    }

    /// Its formats, the usual one first.
    var formats: [ExportFormat] {
        switch self {
        case .video: ExportCategory.video.formats
        case .picture: ExportCategory.picture.formats + ExportCategory.paper.formats
        case .game: [.level, .gltf, .fbx, .lookShader]
        case .print: [.threeMF, .stl, .obj]
        case .web: [.threeJS, .gltf, .usdz]
        case .file: [.gltf, .usdz, .fbx, .obj, .blender, .maps, .ifc]
        }
    }
}
