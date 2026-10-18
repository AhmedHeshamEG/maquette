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
    case mp4, hevc, prores, gif, frames, passes, captions
    case png, picturePasses
    case gltf, fbx, usdz, obj, stl, threeMF, blender, maps, lookShader
    case pdf

    public var id: String { rawValue }

    public var category: ExportCategory {
        switch self {
        case .mp4, .hevc, .prores, .gif, .frames, .passes, .captions: .video
        case .png, .picturePasses: .picture
        case .pdf: .paper
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
        case .png: "PNG"
        case .gltf: "glTF"
        case .fbx: "FBX"
        case .usdz: "USDZ"
        case .obj: "OBJ"
        case .stl: "STL"
        case .threeMF: "3MF"
        case .blender: "Blender"
        case .maps: "Maps (PNG)"
        case .lookShader: "The Look as a shader"
        case .pdf: "PDF"
        }
    }

    /// One line on what it's for.
    public var purpose: String {
        switch self {
        case .mp4: "H.264: plays everywhere, the one to post."
        case .hevc: "Smaller files at the same quality, and see-through video."
        case .prores: "The editing master: every frame whole, with transparency, for Final Cut, Premiere and Resolve."
        case .gif: "A short loop that plays anywhere, even without sound."
        case .frames: "One picture a frame, with the soundtrack as WAV, for any editing app."
        case .passes: "The colour with transparency, and for compositing: the alpha, the depth and a mask per thing."
        case .captions: "Subtitles (.srt and .vtt) from the transcript."
        case .png: "The frame at the playhead, through the shot camera."
        case .picturePasses: "The frame at the playhead with its alpha, its depth and a mask per thing."
        case .gltf, .fbx, .usdz, .obj, .stl, .threeMF, .blender, .maps: modelFormat?.purpose ?? ""
        case .lookShader: "This scene's Look for a game engine: its shader and material, with a licence to use it anywhere."
        case .pdf: "To print or send: the frame on a page, or frames across the shot on one sheet."
        }
    }

    /// The 3D file it writes.
    public var modelFormat: ModelExportFormat? {
        switch self {
        case .gltf: .glb
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
}

/// The named presets, each of one format.
public enum ExportPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case hd1080, vertical, square, hd720
    case youtube4K, hevc1080, transparent
    case prores1080, prores4K
    case gifLoop, gifWide
    case frames1080, frames4K, framesTransparent
    case passes1080, passes4K
    case captions
    case stillHD, still4K, stillTransparent, stillPasses
    case gltfGodot, gltfWeb, gltfApps, fbxUnity, fbxUnreal, usdzQuickLook, objMaterials, stlPrint, threeMFPrint, blenderComputer, mapsPNG
    case shaderGodot, shaderUnity
    case paperFrameA4, paperFrameLetter, paperFrameA3, paperFramesA4, paperFramesLetter

    public var id: String { rawValue }

    public var format: ExportFormat {
        switch self {
        case .hd1080, .vertical, .square, .hd720: .mp4
        case .youtube4K, .hevc1080, .transparent: .hevc
        case .prores1080, .prores4K: .prores
        case .gifLoop, .gifWide: .gif
        case .frames1080, .frames4K, .framesTransparent: .frames
        case .passes1080, .passes4K: .passes
        case .captions: .captions
        case .stillHD, .still4K, .stillTransparent: .png
        case .stillPasses: .picturePasses
        case .gltfGodot, .gltfWeb, .gltfApps: .gltf
        case .fbxUnity, .fbxUnreal: .fbx
        case .usdzQuickLook: .usdz
        case .objMaterials: .obj
        case .stlPrint: .stl
        case .threeMFPrint: .threeMF
        case .blenderComputer: .blender
        case .mapsPNG: .maps
        case .shaderGodot, .shaderUnity: .lookShader
        case .paperFrameA4, .paperFrameLetter, .paperFrameA3, .paperFramesA4, .paperFramesLetter: .pdf
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
        case .pdf: .paper
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
        case .gltfApps, .usdzQuickLook, .objMaterials, .stlPrint, .threeMFPrint, .blenderComputer, .mapsPNG: .apps
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
        default: nil
        }
    }

    /// The settings a picture or video preset stands for (range, audio and quality come from the project and the sheet).
    public func settings(range: TimeRange, fps: Int) -> ExportSettings {
        let video = { (framing: Framing, side: Int, codec: VideoCodecKind) in
            ExportSettings(framing: framing, longSide: side, fps: fps, codec: codec, range: range)
        }
        let short = TimeRange(start: range.start, end: min(range.end, range.start + 6))
        switch self {
        case .hd1080, .stillHD, .frames1080, .passes1080, .stillPasses: return video(.landscape, 1920, .h264)
        case .vertical: return video(.portrait, 1920, .h264)
        case .square: return video(.square, 1080, .h264)
        case .hd720: return video(.landscape, 1280, .h264)
        case .youtube4K, .still4K, .frames4K, .passes4K: return video(.landscape, 3840, .hevc)
        case .hevc1080: return video(.landscape, 1920, .hevc)
        case .transparent:
            return ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .hevcAlpha, range: range, transparent: true)
        case .prores1080: return video(.landscape, 1920, .prores4444)
        case .prores4K: return video(.landscape, 3840, .prores4444)
        case .gifLoop:
            return ExportSettings(framing: .square, longSide: 640, fps: 15, codec: .h264, range: short)
        case .gifWide:
            return ExportSettings(framing: .landscape, longSide: 640, fps: 15, codec: .h264, range: short)
        case .framesTransparent, .stillTransparent:
            return ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .h264, range: range, transparent: true)
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

    public var size: (width: Int, height: Int) { framing.pixelSize(longSide: longSide) }
    public var frameCount: Int { max(Int((range.duration * Double(fps)).rounded()), 1) }

    public var encodeSettings: EncodeSettings {
        EncodeSettings(width: size.width, height: size.height, fps: fps, codec: codec, quality: quality)
    }
}
