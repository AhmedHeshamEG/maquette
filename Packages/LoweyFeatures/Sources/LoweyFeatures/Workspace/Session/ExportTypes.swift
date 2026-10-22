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
    /// A game level's pieces share one texture (G1).
    var atlas = false

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
        case .hdr1080: "HDR 1080p"
        case .hdr4K: "HDR 4K"
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
        case .stillP3: "Wide colour 4K (P3, 16-bit)"
        case .animatic1080: "1080p"
        case .spatial1080: "1080p, both eyes"
        case .video360x4K: "4K (3840 × 1920)"
        case .video360x6K: "6K (5760 × 2880)"
        case .spatialPhotoHD: "HD, both eyes"
        case .panorama6K: "6K"
        case .panorama8K: "8K"
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
        case .storyboardA4: "Storyboard, A4"
        case .storyboardLetter: "Storyboard, US Letter"
        default: guestTitle(of: preset)
        }
    }

    /// G1's presets' names.
    private static func guestTitle(of preset: ExportPreset) -> String {
        switch preset {
        case .psdLayers: "A layer a thing, HD"
        case .inkVector: "The frame's lines"
        case .ifcBuilding: "IFC4, for BIM apps"
        case .levelGodot: "For Godot"
        case .levelUnity: "For Unity"
        case .levelUnreal: "For Unreal"
        case .planPDF: "Plans and elevations, A3 PDF"
        case .planDXF: "Ground floor plan, DXF"
        case .planSVG: "Ground floor plan, SVG"
        case .technicalA4: "A4"
        case .technicalA3: "A3"
        case .papercraftA4: "To print, A4"
        case .papercraftLetter: "To print, US Letter"
        case .laserSVG: "For a laser cutter, SVG"
        default: preset.rawValue
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
        case .storyboardA4, .storyboardLetter: "rectangle.split.3x1"
        case .psdLayers: "square.3.layers.3d.down.right"
        case .inkVector: "scribble"
        case .ifcBuilding, .planPDF, .planDXF, .planSVG: "building.2"
        case .levelGodot, .levelUnity, .levelUnreal: "gamecontroller"
        case .technicalA4, .technicalA3: "ruler"
        case .papercraftA4, .papercraftLetter: "scissors"
        case .laserSVG: "laser.burst"
        case .hdr1080, .hdr4K, .stillP3: "sun.max"
        case .animatic1080: "rectangle.stack"
        case .spatial1080, .spatialPhotoHD: "pano"
        case .video360x4K, .video360x6K, .panorama6K, .panorama8K: "globe.americas"
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
        case .hdr1080, .hdr4K: "Highlights past white and wider colour, for HDR screens (HLG). Final's motion blur isn't drawn in HDR."
        case .stillP3: "Display P3 colour, 16 bits a channel, for print and wide-colour screens."
        case .animatic1080: "Each shot held on its key moment for as long as it lasts, with the sound."
        case .spatial1080, .spatialPhotoHD: "Two eyes a person's width apart; opens in depth on Apple Vision Pro and in Photos."
        case .video360x4K, .video360x6K, .panorama6K, .panorama8K: "All the way round the shot camera; titles and flipbooks stay out."
        case .storyboardA4, .storyboardLetter: "Every shot's key frame with its camera, lens, length and the words said over it."
        case .ifcBuilding: "Walls, floors, roofs, stairs, columns, beams and railings as what they are; rooms as spaces."
        case .levelGodot: "Each piece named …-col, so Godot gives it a body you can't walk through; Godot makes its own lighter copies."
        case .levelUnity: "Lighter copies as _LOD0…2 in a LOD group, and a convex …_collider beside each piece for a Mesh Collider."
        case .levelUnreal: "A convex UCX_… shape beside each piece, which Unreal takes as its collision."
        case .planDXF, .planSVG: "Full size in millimetres: cut walls on their own layer, for AutoCAD, Rhino and Illustrator."
        case .technicalA4, .technicalA3: "First-angle projection (ISO), hidden edges dashed; masses from each part's material."
        case .papercraftA4, .papercraftLetter: "Cut on the solid lines, fold the dashed ones, glue tab to the edge with the same number."
        case .laserSVG: "Red lines cut, blue lines score the folds."
        case .psdLayers: "Each thing on its own layer over the background, named after it."
        default: nil
        }
    }
}
