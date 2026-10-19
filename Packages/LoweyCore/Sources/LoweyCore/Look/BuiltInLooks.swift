import Foundation

public extension LookPreset {
    /// Ink (default): cel shading that holds up close. Soft band edges, hue-shifted shadows, bounce light, contact
    /// shading, rim, darkened-colour lines. The house default.
    static let ink = LookPreset(id: "ink", name: "Ink")

    /// Comic: Ink with halftone dots in the shadows, misregistration for depth of field, animation on twos, heavier
    /// lines and a printed-paper finish (Into the Spider-Verse lineage).
    static let comic = LookPreset(
        id: "comic", name: "Comic",
        shading: ShadingParams(edgeSoftness: 0.012, shadowValue: 0.38, shadowSaturation: 0.15, contactShading: 0.4, rim: 0.45),
        lines: LineParams(width: 2.6, colorMode: .ink, darken: 0.8, creaseAngle: 42, depthSensitivity: 0.6),
        comic: ComicParams(halftone: 0.75, halftoneScale: 7, misregistration: true),
        finish: LookFinish(paperGrain: 0.25, paperTint: 0.35, saturation: 0.08),
        stepping: .onTwos
    )

    /// Sketch: desaturated Ink with pencil lines that boil, paper grain on; objects flagged Accent keep their colour
    /// (Paperman lineage).
    static let sketch = LookPreset(
        id: "sketch", name: "Sketch",
        shading: ShadingParams(edgeSoftness: 0.05, shadowValue: 0.3, shadowSaturation: 0.05, ambientSteps: 0.3, rim: 0.2),
        lines: LineParams(width: 1.4, colorMode: .ink, inkColor: RGBA(0.16, 0.15, 0.17), creaseAngle: 40, depthSensitivity: 0.55,
                          boil: 0.6, pencil: true),
        finish: LookFinish(paperGrain: 0.55, paperTint: 0.12, vignette: 0.15, saturation: -0.88, accentKeepsColor: true)
    )

    /// Clay: soft, warm, rounded (the v1 look on the new renderer): smooth diffuse light, soft shadows, sky light,
    /// fog and bloom, no lines.
    static let clay = LookPreset(
        id: "clay", name: "Clay",
        shading: ShadingParams(model: .clay, edgeSoftness: 0.5, shadowHueShift: 0.08, shadowValue: 0.2, shadowSaturation: 0.04,
                               ambientSteps: 0, contactShading: 0.8, rim: 0.12, specular: 0.25, specularSize: 0.4,
                               specularSoftness: 0.3, posterizeTextures: false, bloom: 0.5, softShadows: true),
        lines: .off
    )

    /// Low-poly: faceted (per-triangle) normals with Ink bands and optional lines (the original Maquette identity).
    static let lowPoly = LookPreset(
        id: "lowPoly", name: "Low-poly",
        shading: ShadingParams(edgeSoftness: 0.02, rim: 0.25, smoothing: 0),
        lines: LineParams(enabled: false, width: 1.2)
    )

    /// Painterly (Arcane, Puss in Boots lineage): three soft bands with strongly coloured shadows, then the whole picture
    /// laid down in brush strokes that follow the forms; thin darkened lines painted with it.
    static let painterly = LookPreset(
        id: "painterly", name: "Painterly",
        shading: ShadingParams(bands: 3, threshold: 0.48, midThreshold: 0.76, edgeSoftness: 0.06, shadowHueShift: 0.32, shadowValue: 0.32,
                               shadowSaturation: 0.18, ambientSteps: 0.5, contactShading: 0.7, rim: 0.4, rimThreshold: 0.6, rimSoftness: 0.08,
                               specular: 0.6, specularSoftness: 0.06, posterizeTextures: false, bloom: 0.4),
        lines: LineParams(width: 1.3, darken: 0.7, creaseAngle: 55, boil: 0.15),
        finish: LookFinish(paperGrain: 0.15, vignette: 0.12, saturation: 0.1),
        paint: PaintStyle(strokes: 0.85, size: 7, wetEdges: 0.1, granulation: 0.1)
    )

    /// Watercolour: light, transparent washes with cool shadows; the paper shows through, washes darken where they
    /// meet and the pigment settles into the grain; a light sepia pencil line.
    static let watercolour = LookPreset(
        id: "watercolour", name: "Watercolour",
        shading: ShadingParams(bands: 3, threshold: 0.46, midThreshold: 0.74, edgeSoftness: 0.08, shadowHueShift: 0.35, shadowValue: 0.22,
                               shadowSaturation: 0.08, ambientSteps: 0.2, contactShading: 0.5, rim: 0.1, specular: 0.2,
                               posterizeTextures: false, bloom: 0.2),
        lines: LineParams(width: 1.0, colorMode: .ink, inkColor: RGBA(0.32, 0.24, 0.2), darken: 0.6, creaseAngle: 60,
                          depthSensitivity: 0.45, boil: 0.3, pencil: true),
        finish: LookFinish(paperGrain: 0.45, paperTint: 0.08, saturation: -0.08),
        paint: PaintStyle(strokes: 0.35, size: 5, wetEdges: 0.75, granulation: 0.6, paper: 0.45)
    )

    /// Gouache: opaque, matte, slightly chalky paint in flat strokes, the paper's tooth in it.
    static let gouache = LookPreset(
        id: "gouache", name: "Gouache",
        shading: ShadingParams(bands: 3, threshold: 0.5, midThreshold: 0.76, edgeSoftness: 0.035, shadowHueShift: 0.3, shadowValue: 0.3,
                               shadowSaturation: 0.1, contactShading: 0.6, rim: 0.2, specular: 0.25, bloom: 0.15),
        lines: LineParams(width: 1.2, darken: 0.65, boil: 0.1),
        finish: LookFinish(paperGrain: 0.55, paperTint: 0.05, saturation: -0.12, lift: 0.04),
        paint: PaintStyle(strokes: 0.6, size: 6, wetEdges: 0.25, granulation: 0.2)
    )

    /// Paperman: soft, filmic light in black and white, thin clean ink drawn over it, grain; things flagged Accent keep
    /// their colour (D-478). Sketch is pencil on paper; this is a film.
    static let paperman = LookPreset(
        id: "paperman", name: "Paperman",
        shading: ShadingParams(model: .clay, edgeSoftness: 0.5, shadowHueShift: 0, shadowValue: 0.25, shadowSaturation: 0, ambientSteps: 0,
                               contactShading: 0.85, rim: 0.25, specular: 0.3, specularSize: 0.35, specularSoftness: 0.25,
                               posterizeTextures: false, bloom: 0.3, softShadows: true),
        lines: LineParams(width: 1.1, colorMode: .ink, inkColor: RGBA(0.1, 0.1, 0.11), creaseAngle: 48, boil: 0.25),
        finish: LookFinish(paperGrain: 0.3, vignette: 0.3, saturation: -1, accentKeepsColor: true, gamma: 0.05)
    )

    /// Anime cel: two hard tones with a lavender shadow, a hard rim and highlight, lines in each thing's own colour,
    /// on twos (D-480).
    static let animeCel = LookPreset(
        id: "animeCel", name: "Anime cel",
        shading: ShadingParams(threshold: 0.52, edgeSoftness: 0.003, shadowHueShift: 0.12, shadowValue: 0.22, shadowSaturation: 0.1,
                               ambientSteps: 1, contactShading: 0.25, rim: 0.6, rimThreshold: 0.72, rimSoftness: 0.005, specular: 1,
                               specularSize: 0.12, specularSoftness: 0.004, bloom: 0.35, shadowTint: RGBA(0.62, 0.58, 0.82, 0.45)),
        lines: LineParams(width: 1.4, darken: 0.85, creaseAngle: 65, depthSensitivity: 0.6),
        finish: LookFinish(saturation: 0.08),
        stepping: .onTwos
    )

    /// Clean product: soft studio light, soft shadows, lacquered surfaces that mirror the room at their edges, no lines
    /// (D-479).
    static let cleanProduct = LookPreset(
        id: "cleanProduct", name: "Clean product",
        shading: ShadingParams(model: .clay, edgeSoftness: 0.5, shadowHueShift: 0.04, shadowValue: 0.15, shadowSaturation: 0.02, ambientSteps: 0,
                               contactShading: 0.9, rim: 0.15, rimThreshold: 0.55, rimSoftness: 0.2, specular: 0.8, specularSize: 0.3,
                               specularSoftness: 0.15, posterizeTextures: false, bloom: 0.15, softShadows: true, reflection: 0.45),
        lines: .off
    )

    /// Pixel: hard toon light in square blocks and few colours, a one-pixel ink line, on twos (D-481).
    static let pixel = LookPreset(
        id: "pixel", name: "Pixel",
        shading: ShadingParams(edgeSoftness: 0.002, ambientSteps: 1, contactShading: 0.5, rim: 0.3, rimSoftness: 0.002, specular: 0.6,
                               specularSoftness: 0.002, bloom: 0),
        lines: LineParams(width: 1, colorMode: .ink, inkColor: RGBA(0.06, 0.05, 0.08), darken: 0.8, creaseAngle: 60, depthSensitivity: 0.6),
        stepping: .onTwos,
        pixel: PixelStyle(size: 4, colors: 8)
    )

    /// The built-in Looks, in the order the Look panel shows them: the toon family, paint, film, solid, pixels.
    static let builtIns: [LookPreset] = [
        .ink, .comic, .sketch, .painterly, .watercolour, .gouache, .paperman, .animeCel, .clay, .cleanProduct, .lowPoly, .pixel
    ]
}

/// Finds Looks by id among the built-ins and a project's own ("My Look") presets.
public enum LookLibrary {
    public static let defaultID = LookPreset.ink.id

    /// The preset for `id`, or Ink when it's unknown (a deleted custom Look never breaks a scene).
    public static func resolve(_ id: String?, custom: [LookPreset] = []) -> LookPreset {
        guard let id else { return .ink }
        return custom.first { $0.id == id } ?? LookPreset.builtIns.first { $0.id == id } ?? .ink
    }

    /// Every Look offered for a project: built-ins, then its own.
    public static func all(custom: [LookPreset]) -> [LookPreset] {
        LookPreset.builtIns + custom.filter { !$0.isBuiltIn }
    }

    /// A unique name for a duplicate ("My Ink", "My Ink 2"…).
    public static func duplicateName(for preset: LookPreset, existing: [LookPreset]) -> String {
        let base = "My \(preset.name)"
        let names = Set(existing.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

public extension Document {
    /// The Look the scene renders with.
    var lookPreset: LookPreset {
        LookLibrary.resolve(effectiveLook.presetID, custom: project.customLooks)
    }

    /// The Look an object renders with: its own override, else the scene's.
    func lookPreset(for object: SceneObject) -> LookPreset {
        guard let id = object.lookOverride else { return lookPreset }
        return LookLibrary.resolve(id, custom: project.customLooks)
    }
}

public extension SceneObject {
    /// This object's own Look (nil = the scene's).
    var lookOverride: String? { properties[.lookPreset]?.stringValue }
    /// Line weight multiplier (1 = the Look's width).
    var lineWeight: Double { properties[.lineWeight]?.floatValue ?? 1 }
    /// Kept in colour by the Sketch Look.
    var isAccent: Bool { properties[.accent]?.boolValue ?? false }
    /// Gets a specular shape (glass, metal, eyes).
    var isGlossy: Bool { properties[.glossy]?.boolValue ?? false }
}

public extension PropertyKey {
    /// A Look id this object uses instead of the scene's.
    static let lookPreset: PropertyKey = "lookPreset"
    /// Line weight multiplier, 0…4.
    static let lineWeight: PropertyKey = "lineWeight"
    /// Shape smoothing override, 0 (faceted) … 1 (smooth).
    static let smoothing: PropertyKey = "smoothing"
    /// Rim light strength override, 0…1.
    static let rimStrength: PropertyKey = "rimStrength"
    /// Glossy material: gets a specular shape.
    static let glossy: PropertyKey = "glossy"
    /// Keeps its colour in the Sketch Look.
    static let accent: PropertyKey = "accent"
    /// In the air on purpose (a drone, a hanging lamp): perception doesn't call it floating.
    static let airborne: PropertyKey = "airborne"
    /// Primitive bevel radius in metres (0 = sharp).
    static let bevel: PropertyKey = "bevel"
    /// Primitive bevel segments (1…6).
    static let bevelSegments: PropertyKey = "bevelSegments"
}
