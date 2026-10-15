import Foundation

/// A material's picture for the library and the Material Studio (D-343): a ball lit from the upper left, drawn on the
/// CPU so it's the same everywhere and needs no renderer. Roughness widens the highlight, metal tints it and darkens
/// the body, bumps tilt the normal, glow adds light.
public enum MaterialPreview {
    public static func render(_ material: PaintMaterial, size: Int, pictures: MaterialPictureSource? = nil,
                              background: RGBA = RGBA(0, 0, 0, 0)) -> RGBAImage {
        var image = RGBAImage(width: size, height: size, color: background)
        let light = normalize3(SIMD3<Float>(-0.5, 0.7, 0.6), fallback: SIMD3<Float>(0, 0, 1))
        let view = SIMD3<Float>(0, 0, 1)
        let radius = Float(size) * 0.46
        let centre = Float(size) / 2
        // The ball is a quarter of a metre across, so materials show at the size they're made for.
        let metres: Float = 0.25
        for y in 0 ..< size {
            for x in 0 ..< size {
                let px = (Float(x) + 0.5 - centre) / radius, py = (centre - Float(y) - 0.5) / radius
                let r2 = px * px + py * py
                guard r2 < 1 else { continue }
                let normal = SIMD3<Float>(px, py, (1 - r2).squareRoot())
                let sample = material.sample(at: normal * metres / 2, normal: normal, pictures: pictures)
                let bumped = tilted(normal, by: material, at: normal * metres / 2, pictures: pictures, height: sample.height)
                let colour = shade(sample, normal: bumped, light: light, view: view)
                // Soft edge: a pixel's worth of coverage.
                let edge = min(max((1 - r2.squareRoot()) * radius, 0), 1)
                image.setPixel(x, y, blend(colour, over: background, alpha: Double(edge)))
            }
        }
        return image
    }

    static func shade(_ s: MaterialSample, normal: SIMD3<Float>, light: SIMD3<Float>, view: SIMD3<Float>) -> SIMD3<Float> {
        let base = s.color.linear
        let diffuse = max(dot3(normal, light), 0)
        let half = normalize3(light + view, fallback: view)
        let power = 4 + pow(1 - s.roughness, 3) * 300
        let highlight = pow(max(dot3(normal, half), 0), power) * (1 - s.roughness * 0.85)
        let specular = SIMD3<Float>(repeating: 0.04) + (base - SIMD3<Float>(repeating: 0.04)) * s.metal
        let fresnel = pow(1 - max(dot3(normal, view), 0), 5)
        var colour = base * (1 - s.metal) * (diffuse * 0.85 + 0.18)
        colour += specular * (highlight * 3 + 0.25 * s.metal) + SIMD3<Float>(repeating: fresnel * 0.12 * (1 - s.roughness))
        colour += s.glow.linear
        return colour.srgb
    }

    /// The normal tilted by the slope of the material's height around the point.
    static func tilted(_ normal: SIMD3<Float>, by material: PaintMaterial, at point: SIMD3<Float>, pictures: MaterialPictureSource?,
                       height: Float) -> SIMD3<Float> {
        guard material.bumps > 0 else { return normal }
        let (t, b) = WearBake.basis(normal)
        let step: Float = 0.002
        let du = material.sample(at: point + t * step, normal: normal, pictures: pictures).height - height
        let dv = material.sample(at: point + b * step, normal: normal, pictures: pictures).height - height
        let depth: Float = 0.004
        return normalize3(normal - t * (du / step * depth) - b * (dv / step * depth), fallback: normal)
    }

    static func blend(_ colour: SIMD3<Float>, over background: RGBA, alpha: Double) -> RGBA {
        let a = alpha + background.a * (1 - alpha)
        guard a > 0 else { return RGBA(0, 0, 0, 0) }
        func mix(_ c: Float, _ b: Double) -> Double { (Double(c) * alpha + b * background.a * (1 - alpha)) / a }
        return RGBA(mix(colour.x, background.r), mix(colour.y, background.g), mix(colour.z, background.b), a)
    }
}

extension SIMD3 where Scalar == Float {
    /// sRGB to linear, per channel.
    var linear: SIMD3<Float> {
        SIMD3<Float>(Float(SceneExport.linear(Double(x))), Float(SceneExport.linear(Double(y))), Float(SceneExport.linear(Double(z))))
    }

    /// Linear to sRGB, per channel (clamped).
    var srgb: SIMD3<Float> {
        SIMD3<Float>(Float(SceneExport.srgb(Double(x))), Float(SceneExport.srgb(Double(y))), Float(SceneExport.srgb(Double(z))))
    }
}

/// An imported PBR set (D-344): the pictures sorted into maps by the words in their names, the way every texture site
/// names them (`oak_basecolor.png`, `Bricks_Roughness.jpg`, `metal_nor_gl.png`…).
public enum PBRSetImport {
    public enum Role: String, Sendable, CaseIterable {
        case color, roughness, metal, normal, height, glow, occlusion, gloss
    }

    /// Each picture's role, by its file name (pictures with no recognisable role are left out). A DirectX-style normal
    /// map (`_dx`) is named so the importer can flip its green.
    public static func classify(_ names: [String]) -> [Role: String] {
        var result: [Role: String] = [:]
        for name in names.sorted() {
            guard let role = role(of: name), result[role] == nil else { continue }
            result[role] = name
        }
        return result
    }

    static let words: [(Role, [String])] = [
        (.occlusion, ["ambientocclusion", "occlusion", "_ao", "-ao", " ao"]),
        (.normal, ["normal", "_nor", "-nor", "_nrm", "_nml", "_n."]),
        (.roughness, ["roughness", "_rough", "-rough", "_rgh"]),
        (.gloss, ["glossiness", "_gloss"]),
        (.metal, ["metallic", "metalness", "_metal", "-metal", "_mtl"]),
        (.height, ["height", "displacement", "_disp", "-disp", "bump", "_h."]),
        (.glow, ["emissive", "emission", "_emit", "glow"]),
        (.color, ["basecolor", "base_color", "albedo", "diffuse", "_diff", "-diff", "_col", "-col", "color", "colour", "_d."])
    ]

    public static func role(of name: String) -> Role? {
        let lower = name.lowercased()
        let stem = (lower as NSString).lastPathComponent
        for (role, keys) in words where keys.contains(where: { stem.contains($0) }) {
            return role
        }
        return nil
    }

    /// Whether a normal map is DirectX-style (green down), by its name.
    public static func isDirectXNormal(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("_dx") || lower.contains("-dx") || lower.contains("directx")
    }

    /// A material for a set: its name from the files' shared start, its pictures from the stored keys.
    public static func material(named name: String, id: String, keys: [Role: String]) -> PaintMaterial {
        PaintMaterial(id: id, name: name, color: .white, roughness: 1, metal: keys[.metal] == nil ? 0 : 1, pattern: .none, scale: 1, variation: 0,
                      bumps: keys[.height] == nil ? 0 : 0.5,
                      pictures: MaterialPictures(color: keys[.color], roughness: keys[.roughness], metal: keys[.metal], height: keys[.height],
                                                 normal: keys[.normal], glow: keys[.glow], occlusion: keys[.occlusion]))
    }

    /// The set's name: the longest start the file names share, tidied ("Oak_Floor_basecolor.png", … → "Oak Floor").
    public static func setName(_ names: [String]) -> String {
        let stems = names.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        guard var prefix = stems.first else { return "Imported" }
        for stem in stems.dropFirst() {
            while !stem.hasPrefix(prefix), !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        let tidy = prefix.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        return tidy.isEmpty ? "Imported" : tidy.prefix(1).uppercased() + tidy.dropFirst()
    }
}
