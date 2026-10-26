import Foundation
import HmmMedia
import LoweyCore

/// Export asks formats first (A1, CONTEXT §10.11): the kind of thing (Video · Picture · 3D · Paper), then the format,
/// then the format's named presets. Each preset is a complete answer; the sheet's options adjust it.
public enum ExportCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case video, picture, model, paper

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .video: "Video"
        case .picture: "Picture"
        case .model: "3D"
        case .paper: "Paper"
        }
    }

    public var systemImage: String {
        switch self {
        case .video: "film"
        case .picture: "photo"
        case .model: "cube"
        case .paper: "doc.richtext"
        }
    }

    public var formats: [ExportFormat] { ExportFormat.allCases.filter { $0.category == self } }
}

/// A file format and what it's for.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case mp4, hevc, prores, gif, frames, passes, captions, animatic, spatialVideo, video360
    case png, picturePasses, spatialPhoto, panorama, psd, inkSVG
    case gltf, threeJS, fbx, usdz, obj, stl, threeMF, blender, maps, lookShader, ifc, level
    case pdf, drawings, technical, papercraft

    public var id: String { rawValue }

    public var category: ExportCategory {
        switch self {
        case .mp4, .hevc, .prores, .gif, .frames, .passes, .captions, .animatic, .spatialVideo, .video360: .video
        case .png, .picturePasses, .spatialPhoto, .panorama, .psd, .inkSVG: .picture
        case .pdf, .drawings, .technical, .papercraft: .paper
        default: .model
        }
    }

    public var title: String {
        switch self {
        case .mp4: "MP4"
        case .hevc: "HEVC"
        case .prores: "ProRes 4444"
        case .gif: "GIF"
        case .frames: "PNG frames"
        case .passes, .picturePasses: "Render passes"
        case .captions: "Captions"
        case .animatic: "Animatic"
        case .spatialVideo: "Spatial video"
        case .video360: "360° video"
        case .png: "PNG"
        case .spatialPhoto: "Spatial photo"
        case .panorama: "360° panorama"
        case .gltf: "glTF"
        case .threeJS: "three.js"
        case .fbx: "FBX"
        case .usdz: "USDZ"
        case .obj: "OBJ"
        case .stl: "STL"
        case .threeMF: "3MF"
        case .blender: "Blender"
        case .maps: "Maps (PNG)"
        case .lookShader: "The Look as a shader"
        case .pdf: "PDF"
        case .psd: "Layered PSD"
        case .inkSVG: "Ink as SVG"
        case .ifc: "IFC"
        case .level: "Game level"
        case .drawings: "Plans & elevations"
        case .technical: "Technical drawing"
        case .papercraft: "Papercraft"
        }
    }

    /// One line on what it's for.
    public var purpose: String {
        switch self {
        case .mp4: "H.264: plays everywhere, the one to post."
        case .hevc: "Smaller files at the same quality, see-through video, and HDR."
        case .prores: "The editing master: every frame whole, with transparency, for Final Cut, Premiere and Resolve."
        case .gif: "A short loop that plays anywhere, even without sound."
        case .frames: "One picture a frame, with the soundtrack as WAV, for any editing app."
        case .passes: "The colour with transparency, and for compositing: the alpha, the depth and a mask per thing."
        case .captions: "Subtitles (.srt and .vtt) from the transcript."
        case .animatic: "Each shot held on one frame for as long as it lasts, with the sound: the film before it moves."
        case .spatialVideo: "In depth on Apple Vision Pro and in Photos: two eyes, a person's width apart."
        case .video360: "All the way round the camera, for YouTube, Quest and any 360 player."
        case .spatialPhoto: "The frame at the playhead in depth, for Apple Vision Pro and Photos."
        case .panorama: "All the way round the camera at the playhead, for Facebook, Google Photos and any 360 viewer."
        case .png: "The frame at the playhead, through the shot camera."
        case .picturePasses: "The frame at the playhead with its alpha, its depth and a mask per thing."
        case .gltf, .threeJS, .fbx, .usdz, .obj, .stl, .threeMF, .blender, .maps: modelFormat?.purpose ?? ""
        case .lookShader: "This scene's Look for a game engine: its shader and material, with a licence to use it anywhere."
        case .pdf: "To print or send: the frame on a page, frames across the shot, or a storyboard of every shot."
        case .psd: "The frame at the playhead with a layer a thing, to draw over in Procreate or Photoshop."
        case .inkSVG: "The frame's lines as vectors, sharp at any size: outlines and creases, hidden lines left out."
        case .ifc: "For Revit, Archicad and every BIM app: walls, floors, roofs, stairs and rooms as what they are."
        case .level: "A level for a game engine: each piece with its collision and lighter copies, named the engine's way."
        case .drawings: "The plan with room areas and the four elevations, black and white, to scale."
        case .technical: "Front, top and side views with sizes, an isometric view and a parts list with materials and mass."
        case .papercraft: "The model unfolded flat with tabs and numbered edges: print, cut, fold and glue, or laser-cut it."
        }
    }

    /// The 3D file it writes.
    public var modelFormat: ModelExportFormat? {
        switch self {
        case .gltf: .glb
        case .threeJS: .web
        case .fbx: .fbx
        case .usdz: .usdz
        case .obj: .obj
        case .stl: .stl
        case .threeMF: .threeMF
        case .blender: .blender
        case .maps: .textures
        default: nil
        }
    }

    public var presets: [ExportPreset] { ExportPreset.allCases.filter { $0.format == self } }
}

/// What an export makes, once its preset is picked.
public enum ExportKind: String, Sendable, Codable {
    case video, gif, frames, passes, captions, still, stillPasses, model, lookShader, paper
    case animatic, spatialVideo, video360, spatialPhoto, panorama, storyboard
    /// G1's files for the guests (drawings, IFC, levels, papercraft, layered pictures).
    case guest
}

/// The named presets, each of one format.
public enum ExportPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case hd1080, vertical, square, hd720
    case youtube4K, hevc1080, transparent, hdr1080, hdr4K
    case prores1080, prores4K
    case gifLoop, gifWide
    case frames1080, frames4K, framesTransparent
    case passes1080, passes4K
    case captions
    case stillHD, still4K, stillTransparent, stillP3, stillPasses
    case animatic1080, spatial1080, video360x4K, video360x6K, spatialPhotoHD, panorama6K, panorama8K
    case gltfGodot, gltfWeb, gltfApps, threeFolder, fbxUnity, fbxUnreal, usdzQuickLook, objMaterials, stlPrint, threeMFPrint, blenderComputer, mapsPNG
    case shaderGodot, shaderUnity
    case paperFrameA4, paperFrameLetter, paperFrameA3, paperFramesA4, paperFramesLetter, storyboardA4, storyboardLetter
    case psdLayers, inkVector, ifcBuilding, levelGodot, levelUnity, levelUnreal, planPDF, planDXF, planSVG, technicalA4, technicalA3
    case papercraftA4, papercraftLetter, laserSVG

    public var id: String { rawValue }

    public var format: ExportFormat {
        switch self {
        case .hd1080, .vertical, .square, .hd720: .mp4
        case .youtube4K, .hevc1080, .transparent, .hdr1080, .hdr4K: .hevc
        case .prores1080, .prores4K: .prores
        case .gifLoop, .gifWide: .gif
        case .frames1080, .frames4K, .framesTransparent: .frames
        case .passes1080, .passes4K: .passes
        case .captions: .captions
        case .stillHD, .still4K, .stillTransparent, .stillP3: .png
        case .animatic1080: .animatic
        case .spatial1080: .spatialVideo
        case .video360x4K, .video360x6K: .video360
        case .spatialPhotoHD: .spatialPhoto
        case .panorama6K, .panorama8K: .panorama
        case .stillPasses: .picturePasses
        case .gltfGodot, .gltfWeb, .gltfApps: .gltf
        case .threeFolder: .threeJS
        case .fbxUnity, .fbxUnreal: .fbx
        case .usdzQuickLook: .usdz
        case .objMaterials: .obj
        case .stlPrint: .stl
        case .threeMFPrint: .threeMF
        case .blenderComputer: .blender
        case .mapsPNG: .maps
        case .shaderGodot, .shaderUnity: .lookShader
        case .paperFrameA4, .paperFrameLetter, .paperFrameA3, .paperFramesA4, .paperFramesLetter, .storyboardA4, .storyboardLetter: .pdf
        case .psdLayers: .psd
        case .inkVector: .inkSVG
        case .ifcBuilding: .ifc
        case .levelGodot, .levelUnity, .levelUnreal: .level
        case .planPDF, .planDXF, .planSVG: .drawings
        case .technicalA4, .technicalA3: .technical
        case .papercraftA4, .papercraftLetter, .laserSVG: .papercraft
        }
    }

    public var kind: ExportKind {
        switch format {
        case .mp4, .hevc, .prores: .video
        case .gif: .gif
        case .frames: .frames
        case .passes: .passes
        case .captions: .captions
        case .png: .still
        case .picturePasses: .stillPasses
        case .lookShader: .lookShader
        case .pdf: self == .storyboardA4 || self == .storyboardLetter ? .storyboard : .paper
        case .animatic: .animatic
        case .spatialVideo: .spatialVideo
        case .video360: .video360
        case .spatialPhoto: .spatialPhoto
        case .panorama: .panorama
        case .psd, .inkSVG, .ifc, .level, .drawings, .technical, .papercraft: .guest
        default: .model
        }
    }

    /// The 3D file's preset: what the scene loses or gains on the way out.
    public var model: ModelPreset? {
        switch self {
        case .gltfGodot: .godot
        case .gltfWeb: .web
        case .fbxUnity: .unity
        case .fbxUnreal: .unreal
        case .gltfApps, .threeFolder, .usdzQuickLook, .objMaterials, .stlPrint, .threeMFPrint, .blenderComputer, .mapsPNG: .apps
        default: nil
        }
    }

    /// A game level's engine (G1).
    public var levelEngine: GameEngine? {
        switch self {
        case .levelGodot: .godot
        case .levelUnity: .unity
        case .levelUnreal: .unreal
        default: nil
        }
    }

    public var shaderEngine: LookShaderExport.Engine? {
        switch self {
        case .shaderGodot: .godot
        case .shaderUnity: .unity
        default: nil
        }
    }

    public var paper: (size: PaperSize, frames: Bool)? {
        switch self {
        case .paperFrameA4: (.a4, false)
        case .paperFrameLetter: (.letter, false)
        case .paperFrameA3: (.a3, false)
        case .paperFramesA4: (.a4, true)
        case .paperFramesLetter: (.letter, true)
        case .storyboardA4: (.a4, true)
        case .storyboardLetter: (.letter, true)
        default: nil
        }
    }

    /// The settings a picture or video preset stands for (range, audio and quality come from the project and the sheet).
    /// Presets that are a size come out in the scene's `frame` (2.39:1 at 1080p is 1920 × 802); the shaped ones (Shorts,
    /// Square, the GIF loops) keep their shape.
    public func settings(range: TimeRange, fps: Int, frame: Framing = .landscape) -> ExportSettings {
        let video = { (framing: Framing, side: Int, codec: VideoCodecKind) in
            ExportSettings(framing: framing == .landscape ? frame : framing, longSide: side, fps: fps, codec: codec, range: range)
        }
        let short = TimeRange(start: range.start, end: min(range.end, range.start + 6))
        switch self {
        case .hd1080, .stillHD, .frames1080, .passes1080, .stillPasses: return video(.landscape, 1920, .h264)
        case .vertical: return video(.portrait, 1920, .h264)
        case .square: return video(.square, 1080, .h264)
        case .hd720: return video(.landscape, 1280, .h264)
        case .youtube4K, .still4K, .frames4K, .passes4K: return video(.landscape, 3840, .hevc)
        case .hevc1080: return video(.landscape, 1920, .hevc)
        case .hdr1080: return video(.landscape, 1920, .hevcHDR)
        case .hdr4K: return video(.landscape, 3840, .hevcHDR)
        case .stillP3:
            var settings = video(.landscape, 3840, .h264)
            settings.wideColour = true
            return settings
        case .animatic1080: return video(.landscape, 1920, .h264)
        case .spatial1080: return video(.landscape, 1920, .hevc)
        case .spatialPhotoHD: return video(.landscape, 2560, .hevc)
        case .video360x4K, .panorama6K, .video360x6K, .panorama8K:
            let side = self == .video360x4K ? 3840 : self == .panorama8K ? 8192 : 5760
            var settings = ExportSettings(framing: .landscape, longSide: side, fps: fps, codec: side > 4096 ? .hevc : .h264, range: range)
            settings.panorama = true
            return settings
        case .transparent:
            return ExportSettings(framing: frame, longSide: 1920, fps: fps, codec: .hevcAlpha, range: range, transparent: true)
        case .prores1080: return video(.landscape, 1920, .prores4444)
        case .prores4K: return video(.landscape, 3840, .prores4444)
        case .gifLoop:
            return ExportSettings(framing: .square, longSide: 640, fps: 15, codec: .h264, range: short)
        case .gifWide:
            return ExportSettings(framing: .landscape, longSide: 640, fps: 15, codec: .h264, range: short)
        case .framesTransparent, .stillTransparent:
            return ExportSettings(framing: frame, longSide: 1920, fps: fps, codec: .h264, range: range, transparent: true)
        default: return video(.landscape, 1920, .h264)
        }
    }
}

/// What a 3D preset does to the scene on the way out.
public enum ModelPreset: String, Sendable, Codable {
    /// Godot: things, their colliders and their motion; the engine brings cameras and lights.
    case godot
    /// The web (three.js and model viewers): painted colour as vertex colours, a small file; no colliders.
    case web
    /// Unity and Unreal: the rigged thing with its joints named for the engine's retargeting.
    case unity, unreal
    /// Other 3D apps: everything, as it is.
    case apps

    public var engine: GameEngine? {
        switch self {
        case .unity: .unity
        case .unreal: .unreal
        default: nil
        }
    }

    /// The scene as this preset writes it.
    public func prepared(_ scene: CoreScene) -> CoreScene {
        switch self {
        case .godot: ExportPrep.withoutCamerasAndLights(scene)
        case .web: ExportPrep.withoutPhysics(scene)
        case .unity, .unreal: ExportPrep.withoutPhysics(ExportPrep.withoutCamerasAndLights(scene))
        case .apps: scene
        }
    }
}

/// Everything one video export needs.
public struct ExportSettings: Sendable, Hashable, Codable {
    public var framing: Framing
    /// Long side in pixels (1920 = HD, 3840 = 4K).
    public var longSide: Int
    /// 24, 25, 30 or 60.
    public var fps: Int
    public var codec: VideoCodecKind
    public var range: TimeRange
    public var transparent: Bool
    /// 0…1 (0.5 = the preset's bitrate).
    public var quality: Double
    /// Final (A1): motion blur, anti-aliasing past the preview's, the best shadows and the finest water.
    public var final: Bool = false
    /// Only these things are drawn (the rest of the scene is left out); nil draws everything.
    public var only: [ObjectID]?
    /// 360° (F1): all the way round the camera, a 2:1 equirectangular frame `longSide` wide.
    public var panorama: Bool = false
    /// Display P3 colour in 16 bits (stills).
    public var wideColour: Bool = false
    /// Stereo (spatial video and photos): how far apart the eyes are against a person's (0.5 flatter … 2 deeper).
    public var stereoDepth: Double = 1

    public init(framing: Framing, longSide: Int, fps: Int, codec: VideoCodecKind, range: TimeRange, transparent: Bool = false,
                quality: Double = 0.5) {
        self.framing = framing
        self.longSide = longSide
        self.fps = fps
        // A see-through video needs a codec with alpha: HEVC's, unless it's ProRes 4444 (which always has one).
        self.codec = transparent && !codec.hasAlpha ? .hevcAlpha : codec
        self.range = range
        self.transparent = transparent
        self.quality = quality
    }

    public static let frameRates = [24, 25, 30, 60]

    public var size: (width: Int, height: Int) {
        guard panorama else { return framing.pixelSize(longSide: longSide) }
        let width = longSide - longSide % 4
        return (width, width / 2)
    }

    /// How the frame's colour is written.
    public var encoding: FrameEncoding { codec.isHDR ? .hdr : wideColour ? .displayP3 : .sRGB }
    public var frameCount: Int { max(Int((range.duration * Double(fps)).rounded()), 1) }

    public var encodeSettings: EncodeSettings {
        EncodeSettings(width: size.width, height: size.height, fps: fps, codec: codec, quality: quality)
    }
}
