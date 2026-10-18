import Foundation
import LoweyCore
import LoweyEngine

/// One export, as the sheet hands it over (A1): the preset, its settings, and the options beside it.
struct ExportJob: Sendable {
    var preset: ExportPreset
    var settings: ExportSettings
    /// One file per scene of the project (Video, Picture, Paper).
    var everyScene = false
    /// One file per shot: the stretches between the timeline's camera cuts (Video).
    var everyShot = false
    /// Only the selected things are drawn or written.
    var onlySelection = false
    /// How a glTF carries painted colour.
    var paintColors: PaintColorOutput = .texture

    var title: String { preset.format.title + " · " + ExportPreset.title(of: preset) }
}

extension ExportPreset {
    /// The preset's name under its format ("1080p", "For Godot").
    static func title(of preset: ExportPreset) -> String {
        switch preset {
        case .hd1080: "1080p"
        case .vertical: "Shorts / Reels 9:16"
        case .square: "Square"
        case .hd720: "720p"
        case .youtube4K: "YouTube 4K"
        case .hevc1080: "1080p"
        case .transparent: "Transparent 1080p"
        case .prores1080: "1080p"
        case .prores4K: "4K"
        case .gifLoop: "Square loop"
        case .gifWide: "Wide loop"
        case .frames1080, .passes1080: "1080p"
        case .frames4K, .passes4K: "4K"
        case .framesTransparent: "Transparent 1080p"
        case .captions: ".srt and .vtt"
        case .stillHD: "HD"
        case .still4K: "4K"
        case .stillTransparent: "Transparent HD"
        case .stillPasses: "HD"
        case .gltfGodot: "For Godot"
        case .gltfWeb: "For the web"
        case .gltfApps: "For Blender and 3D apps"
        case .fbxUnity: "For Unity"
        case .fbxUnreal: "For Unreal"
        case .usdzQuickLook: "For AR Quick Look"
        case .objMaterials: "With its materials"
        case .stlPrint, .threeMFPrint: "For printing"
        case .blenderComputer: "Render on a computer"
        case .mapsPNG: "Every painted map"
        case .shaderGodot: "For Godot"
        case .shaderUnity: "For Unity (URP)"
        case .paperFrameA4: "This frame, A4"
        case .paperFrameLetter: "This frame, US Letter"
        case .paperFrameA3: "This frame, A3"
        case .paperFramesA4: "Frames across the shot, A4"
        case .paperFramesLetter: "Frames across the shot, US Letter"
        }
    }

    /// The preset's icon.
    static func symbol(of preset: ExportPreset) -> String {
        switch preset {
        case .vertical: "rectangle.portrait"
        case .square, .gifLoop: "square"
        case .transparent, .framesTransparent, .stillTransparent: "square.dashed"
        case .gifWide: "repeat"
        case .frames1080, .frames4K: "photo.stack"
        case .passes1080, .passes4K, .stillPasses: "square.3.layers.3d"
        case .captions: "captions.bubble"
        case .stillHD, .still4K: "photo"
        case .gltfGodot, .fbxUnity, .fbxUnreal, .shaderGodot, .shaderUnity: "gamecontroller"
        case .gltfWeb: "globe"
        case .gltfApps, .objMaterials: "cube"
        case .usdzQuickLook: "arkit"
        case .stlPrint, .threeMFPrint: "printer"
        case .blenderComputer: "desktopcomputer"
        case .mapsPNG: "square.grid.3x3"
        case .paperFrameA4, .paperFrameLetter, .paperFrameA3: "doc.richtext"
        case .paperFramesA4, .paperFramesLetter: "rectangle.split.3x3"
        default: "play.rectangle"
        }
    }

    /// A line under the preset when it needs one (the Blender package is close to the Look, never identical).
    static func note(of preset: ExportPreset) -> String? {
        switch preset {
        case .blenderComputer: "Blender renders it close to this Look, never identical."
        case .gltfGodot: "Things, their colliders and their motion; Godot brings its own cameras and lights."
        case .gltfWeb: "Painted colour as vertex colours, for a small file three.js and model viewers open."
        case .fbxUnity: "The rigged thing with its joints named for Unity's humanoid."
        case .fbxUnreal: "The rigged thing with its joints named for Unreal's mannequin."
        case .shaderGodot, .shaderUnity: "Close to this Look, never identical: the whole picture's effects stay in Maquette."
        default: nil
        }
    }
}
