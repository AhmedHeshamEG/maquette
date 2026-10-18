import Foundation

/// A Look as a shader for a game engine (A1, "take the Look with you"): the cel bands, the hue-shifted shadows, the rim
/// light, stepped highlights and the lines as an outline pass, with the Look's own numbers. Godot gets a `.gdshader`, its
/// outline and a material (`.tres`); Unity's Universal Render Pipeline gets one `.shader` with both passes. Effects of the
/// whole picture (halftone, paper grain, misregistration, boiling lines) stay in Maquette: the files say so.
public enum LookShaderExport {
    public enum Engine: String, CaseIterable, Sendable, Identifiable {
        case godot, unity

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .godot: "Godot"
            case .unity: "Unity (URP)"
            }
        }
    }

    /// The files for `engine`, named after the Look, with the licence and a short read-me.
    public static func files(_ preset: LookPreset, engine: Engine, author: String? = nil) -> [(name: String, data: Data)] {
        let stem = "maquette_" + slug(preset.name)
        let numbers = LookShaderNumbers(preset)
        var files: [(String, String)] = switch engine {
        case .godot:
            [
                ("\(stem).gdshader", GodotLookShader.surface(numbers, name: preset.name)),
                ("\(stem)_outline.gdshader", GodotLookShader.outline(numbers, name: preset.name)),
                ("\(stem).tres", GodotLookShader.material(numbers, stem: stem))
            ]
        case .unity:
            [("\(stem).shader", UnityLookShader.shader(numbers, name: preset.name))]
        }
        files.append(("LICENSE.txt", ExportLicence.text(for: "the \(preset.name) Look's shader files", author: author)))
        files.append(("README.txt", readMe(preset.name, engine: engine, stem: stem)))
        return files.map { (name: $0.0, data: Data($0.1.utf8)) }
    }

    /// The files in one zip, named for the person to find ("Ink Look for Godot.zip").
    public static func archive(_ preset: LookPreset, engine: Engine, author: String? = nil) -> (name: String, data: Data) {
        let folder = "\(preset.name) Look for \(engine == .godot ? "Godot" : "Unity")"
        let files = files(preset, engine: engine, author: author).map { (name: "\(folder)/\($0.name)", data: $0.data) }
        return ("\(folder).zip", ZipWriter.storedArchive(files))
    }

    /// Lower-case letters, digits and underscores (a file and shader name every engine accepts).
    static func slug(_ name: String) -> String {
        let kept = name.lowercased().map { ($0.isLetter && $0.isASCII) || $0.isNumber ? $0 : "_" }
        let joined = String(kept).split(separator: "_").joined(separator: "_")
        return joined.isEmpty ? "look" : joined
    }

    static func readMe(_ name: String, engine: Engine, stem: String) -> String {
        let how = switch engine {
        case .godot:
            """
            Put this folder anywhere in your Godot 4 project. Drag \(stem).tres onto a MeshInstance3D's material (or its
            Surface Material Override) and set its albedo. The outline is its next pass: change its line colour there.
            It takes light from your DirectionalLight3D and other lights, and shadows when they cast them.
            """
        case .unity:
            """
            Put \(stem).shader in your Unity project's Assets (Universal Render Pipeline). Create a Material, choose
            Maquette/\(name) as its shader and set its colour. It takes the main light and its shadows; the outline is
            its second pass.
            """
        }
        return """
        The \(name) Look from Maquette, as a shader.

        \(how)

        What travels: the light and shadow bands, the shadows' colour, the rim light, the highlights on glossy things
        and the lines (as an outline). What stays in Maquette: effects of the whole picture (halftone dots, paper grain,
        misregistration, boiling lines, contact shading). Close to the Look, never identical.

        """
    }
}

/// The Look's numbers as both engines use them.
struct LookShaderNumbers {
    var bands: Int
    var threshold, midThreshold, edgeSoftness: Double
    var shadowHueShift, shadowValue, shadowSaturation: Double
    var rim, rimThreshold, rimSoftness: Double
    var specular, specularSize, specularSoftness: Double
    var faceted, clay, lines: Bool
    var lineWidth: Double
    var lineColor: RGBA
    var darkenedLines: Bool
    var darken: Double

    init(_ preset: LookPreset) {
        let shading = preset.shading
        bands = shading.bands
        threshold = shading.threshold
        midThreshold = shading.midThreshold
        edgeSoftness = shading.edgeSoftness
        shadowHueShift = shading.shadowHueShift
        shadowValue = shading.shadowValue
        shadowSaturation = shading.shadowSaturation
        rim = shading.rim
        rimThreshold = shading.rimThreshold
        rimSoftness = shading.rimSoftness
        specular = shading.specular
        specularSize = shading.specularSize
        specularSoftness = shading.specularSoftness
        faceted = shading.smoothing < 0.5
        clay = shading.model == .clay
        lines = preset.lines.enabled
        lineWidth = preset.lines.width
        lineColor = preset.lines.inkColor
        darkenedLines = preset.lines.colorMode == .darkened
        darken = preset.lines.darken
    }

    /// A number as shader source ("0.5000"), the same on every device.
    static func f(_ value: Double) -> String { String(format: "%.4f", value) }
}

/// The licence exported files carry (CONTEXT §10.11: exported shaders, Looks and kit items are the person's to use).
public enum ExportLicence {
    public static func text(for what: String, author: String? = nil) -> String {
        let by = author.flatMap { $0.isEmpty ? nil : "Made by \($0) with Maquette." } ?? "Made with Maquette."
        return """
        \(by)

        You may use \(what) in anything you make, commercial included: games, films, apps, prints. Change them, share
        them, sell what you make with them. No credit is needed.

        They come as they are, without any warranty.

        """
    }
}
