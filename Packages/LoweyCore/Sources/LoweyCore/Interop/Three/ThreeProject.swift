import Foundation

/// Export ▸ For the web (X1): a folder anyone (or any agent) can open and build on. The GLB written for three.js
/// (`ThreeNames`), the same scene in three.js's own JSON (`ThreeObjectJSON`), a player (`index.html` + `main.js`: the
/// camera cuts, the timeline on an `AnimationMixer`, the Look), a React Three Fiber component, `AGENTS.md` and the
/// pinned three.js carried inside, so nothing needs the network.
public enum ThreeProject {
    /// three.js files the folder carries (from HmmWeb's copy, three r170), under `lib/three/`.
    public static let libraryFiles = [
        "three.module.js", "LICENSE",
        "addons/loaders/GLTFLoader.js", "addons/utils/BufferGeometryUtils.js", "addons/controls/OrbitControls.js",
        "addons/effects/OutlineEffect.js",
        "addons/postprocessing/EffectComposer.js", "addons/postprocessing/Pass.js", "addons/postprocessing/MaskPass.js",
        "addons/postprocessing/ShaderPass.js", "addons/postprocessing/HalftonePass.js", "addons/postprocessing/RenderPixelatedPass.js",
        "addons/postprocessing/OutputPass.js",
        "addons/shaders/CopyShader.js", "addons/shaders/HalftoneShader.js", "addons/shaders/OutputShader.js"
    ]
    /// The three.js version the folder pins (and `Scene.jsx` asks npm for).
    public static let threeVersion = "0.170.0"

    /// What goes in: the scene as exported (`glb` from `GLTFScene.glb`), its Look, and how to read a three.js file.
    public struct Input {
        public var scene: Scene
        public var look: Look
        public var preset: LookPreset
        public var glb: Data
        public var name: String
        public var author: String?
        public var library: (String) -> Data?

        public init(scene: Scene, look: Look, preset: LookPreset, glb: Data, name: String, author: String? = nil,
                    library: @escaping (String) -> Data?) {
            self.scene = scene
            self.look = look
            self.preset = preset
            self.glb = glb
            self.name = name
            self.author = author
            self.library = library
        }
    }

    /// Every file of the folder, by its path inside it.
    public static func files(_ input: Input) throws -> [(name: String, data: Data)] {
        let glb = ThreeNames.prepared(input.glb)
        let contents = try ThreeContents(glb: glb)
        var files: [(String, Data)] = try [
            ("index.html", Data(ThreeProjectScripts.indexHTML.replacingOccurrences(of: "{{TITLE}}", with: html(input.name)).utf8)),
            ("main.js", Data(ThreeProjectScripts.mainJS.utf8)),
            ("maquette/pointer.js", Data(ThreeProjectScripts.pointerJS.utf8)),
            ("maquette/look.js", Data(ThreeProjectScripts.lookJS.utf8)),
            ("maquette/scene.js", Data(sceneInfo(input, contents: contents).utf8)),
            ("scene.glb", glb),
            ("scene.json", ThreeObjectJSON.data(fromGLB: glb)),
            ("Scene.jsx", Data(ThreeComponent.source(contents).utf8)),
            ("AGENTS.md", Data(ThreeAgents.text(contents, name: input.name, look: input.preset.name).utf8)),
            ("LICENSE.txt", Data(ExportLicence.text(for: "this scene's files and its Look's scripts", author: input.author).utf8))
        ]
        for path in libraryFiles {
            guard let data = input.library(path) else { throw ExportFailure.missingLibrary(path) }
            files.append(("lib/three/\(path)", data))
        }
        return files.map { (name: $0.0, data: $0.1) }
    }

    /// The folder in one zip ("Room for the web.zip").
    public static func archive(_ input: Input) throws -> (name: String, data: Data) {
        let folder = "\(input.name) for the web"
        let files = try files(input).map { (name: "\(folder)/\($0.name)", data: $0.data) }
        return ("\(folder).zip", ZipWriter.storedArchive(files))
    }

    public enum ExportFailure: Error, Equatable, CustomStringConvertible {
        case missingLibrary(String)

        public var description: String {
            switch self {
            case let .missingLibrary(path): "three.js's \(path) is missing from the app."
            }
        }
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: scene.js

    /// The numbers the player needs beside the GLB: the timeline, the camera cuts by three.js name, the sky, sun and
    /// ground, and the Look.
    static func sceneInfo(_ input: Input, contents: ThreeContents) -> String {
        let timeline = input.scene.timeline
        let lighting = input.look.lighting, sky = input.look.sky, ground = input.look.ground
        let hex: (RGBA) -> Int = { Int(($0.r * 255).rounded()) << 16 | Int(($0.g * 255).rounded()) << 8 | Int(($0.b * 255).rounded()) }
        let direction = lighting.sunDirection
        var info: [String: Any] = [
            "name": input.name, "fps": timeline.fps, "duration": timeline.duration, "clip": contents.clips.first?.name ?? NSNull(),
            "activeCamera": input.scene.activeCamera.flatMap { contents.threeName[$0] } ?? NSNull(),
            "cuts": timeline.cuts.sorted { $0.time < $1.time }.compactMap { cut in
                contents.threeName[cut.camera].map { ["time": cut.time, "camera": $0] as [String: Any] }
            },
            "sky": ["top": hex(sky.top), "horizon": hex(sky.horizon), "ground": hex(ground.color), "ambient": lighting.ambientIntensity * .pi],
            "sun": ["direction": [direction.x, direction.y, direction.z], "color": hex(lighting.sunColor), "intensity": lighting.sunIntensity * .pi,
                    "shadows": lighting.sunShadows],
            "ground": ["visible": ground.visible, "color": hex(ground.color), "radius": ground.size],
            "look": lookNumbers(input.preset)
        ]
        if input.scene.activeCamera == nil { info["activeCamera"] = contents.cameras.first ?? NSNull() }
        let data = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return "// Made with Maquette: the timeline, the camera cuts, the light and the Look of \(input.name).\n"
            + "export const MAQUETTE = \(String(decoding: data, as: UTF8.self));\n"
    }

    /// The Look's numbers three.js uses (`maquette/look.js`).
    static func lookNumbers(_ preset: LookPreset) -> [String: Any] {
        let shading = preset.shading
        var look: [String: Any] = [
            "name": preset.name, "model": shading.model.rawValue, "bands": shading.bands, "threshold": shading.threshold,
            "midThreshold": shading.midThreshold, "edgeSoftness": shading.edgeSoftness, "shadowValue": shading.shadowValue,
            "faceted": shading.smoothing < 0.5
        ]
        let ink = preset.lines.inkColor
        look["lines"] = preset.lines.enabled && preset.lines.width > 0
            ? ["width": preset.lines.width, "color": Int((ink.r * 255).rounded()) << 16 | Int((ink.g * 255).rounded()) << 8 | Int((ink.b * 255).rounded())]
            : NSNull()
        look["halftone"] = preset.comic.halftone > 0 ? ["amount": preset.comic.halftone, "scale": preset.comic.halftoneScale] : NSNull()
        look["pixel"] = preset.pixel.map { ["size": max(Int($0.size.rounded()), 1), "colors": $0.colors] } ?? NSNull()
        return look
    }
}
