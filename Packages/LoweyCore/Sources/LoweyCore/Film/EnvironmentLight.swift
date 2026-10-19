import Foundation

/// An HDRI as the world's light (F1): the picture stands behind everything as the sky, and lights the scene the way
/// the place it was taken did. The sun is found in the picture (the brightest patch: its direction, colour and how much
/// of the light it carries), the sky's three colours are the picture's own above, at and below the horizon, and the
/// ambient light is how bright the rest of it is. Maquette's shading stays a Look (bands, lines), so the HDRI drives the
/// same sun and sky every Look already reads; nothing about a Look changes.
public struct EnvironmentLight: Hashable, Sendable {
    public var sunAzimuth: Double
    public var sunElevation: Double
    public var sunColor: RGBA
    /// 0.15 (overcast: no sun to speak of) … 1.6 (a clear midday).
    public var sunIntensity: Double
    public var ambientIntensity: Double
    public var sky: Sky
    /// The picture's average brightness, for the background's exposure.
    public var meanLuminance: Double

    /// Reads the light out of a map (any size; the analysis works on a 256-wide copy).
    public static func analyse(_ map: RadianceHDR, turn degrees: Double = 0) -> EnvironmentLight {
        let small = map.width > 256 ? shrink(map, to: 256) : map
        var total = 0.0
        var peak = 0.0
        var weighted = 0.0
        for row in 0 ..< small.height {
            let solid = sin((Double(row) + 0.5) / Double(small.height) * .pi)
            for column in 0 ..< small.width {
                let luminance = luma(small, column, row)
                total += luminance * solid
                weighted += solid
                peak = max(peak, luminance)
            }
        }
        let mean = total / max(weighted, 1e-9)
        // The sun: everything brighter than a third of the peak, above the horizon, weighted by how bright it is.
        var sunEnergy = 0.0
        var sunVector = Vec3.zero
        var sunRGB = Vec3.zero
        for row in 0 ..< small.height / 2 {
            let solid = sin((Double(row) + 0.5) / Double(small.height) * .pi)
            for column in 0 ..< small.width {
                let luminance = luma(small, column, row)
                guard luminance > peak / 3 else { continue }
                let energy = luminance * solid
                sunEnergy += energy
                sunVector += small.direction(column: column, row: row) * energy
                let index = (row * small.width + column) * 3
                sunRGB += Vec3(Double(small.pixels[index]), Double(small.pixels[index + 1]), Double(small.pixels[index + 2])) * solid
            }
        }
        let share = sunEnergy / max(total, 1e-9)
        let toSun = sunVector.length > 1e-9 ? sunVector.normalized : Vec3(0, 1, 0)
        let turned = Quat(angle: degrees * .pi / 180, axis: .unitY).act(toSun)
        let elevation = asin(max(-1, min(1, turned.y))) * 180 / .pi
        let azimuth = atan2(turned.x, turned.z) * 180 / .pi
        // A sky with no clear sun (overcast, a studio's soft boxes) shades softly from above.
        let clear = peak > mean * 8
        return EnvironmentLight(
            sunAzimuth: azimuth, sunElevation: clear ? max(elevation, 3) : 60, sunColor: normalised(sunRGB),
            sunIntensity: clear ? min(max(share * 3, 0.15), 1.6) : 0.15, ambientIntensity: min(max(0.25 + (1 - share) * 0.75, 0.25), 1.1),
            sky: Sky(top: band(small, from: 0, to: 0.17, mean: mean), horizon: band(small, from: 0.45, to: 0.53, mean: mean),
                     bottom: band(small, from: 0.7, to: 1, mean: mean)),
            meanLuminance: mean
        )
    }

    /// The Look lit by the map: the sun, its colour and strength, the ambient light and the sky. The map shows behind
    /// the scene (`Sky.environment`); the ground keeps its colour.
    public func applied(to look: Look, environment: String, turn: Double) -> Look {
        var lit = look
        lit.lighting.sunAzimuth = sunAzimuth
        lit.lighting.sunElevation = sunElevation
        lit.lighting.sunColor = sunColor
        lit.lighting.sunIntensity = sunIntensity
        lit.lighting.ambientIntensity = ambientIntensity
        lit.lighting.realSun = nil
        var sky = sky
        sky.environment = environment
        sky.environmentTurn = turn
        sky.environmentExposure = meanLuminance > 0 ? -log2(meanLuminance / 0.18) : 0
        lit.sky = sky
        lit.lightingPreset = nil
        return lit
    }

    static func luma(_ map: RadianceHDR, _ column: Int, _ row: Int) -> Double {
        let index = (row * map.width + column) * 3
        return Double(map.pixels[index]) * 0.2126 + Double(map.pixels[index + 1]) * 0.7152 + Double(map.pixels[index + 2]) * 0.0722
    }

    /// The band's average colour, exposed so the picture's middle grey sits at 0.18 and shown as display colour.
    static func band(_ map: RadianceHDR, from top: Double, to bottom: Double, mean: Double) -> RGBA {
        let first = Int(top * Double(map.height))
        let last = max(Int(bottom * Double(map.height)), first + 1)
        var sum = Vec3.zero
        var count = 0.0
        for row in first ..< min(last, map.height) {
            for column in 0 ..< map.width {
                let index = (row * map.width + column) * 3
                sum += Vec3(Double(map.pixels[index]), Double(map.pixels[index + 1]), Double(map.pixels[index + 2]))
                count += 1
            }
        }
        let exposure = 0.18 / max(mean, 1e-9)
        let linear = sum * (exposure / max(count, 1))
        // Highlights roll off rather than clip (a sun in the top band).
        func display(_ value: Double) -> Double { SceneExport.srgb(value / (1 + value)) * 1.5 }
        return RGBA(min(display(linear.x), 1), min(display(linear.y), 1), min(display(linear.z), 1))
    }

    static func normalised(_ rgb: Vec3) -> RGBA {
        let peak = max(rgb.x, rgb.y, rgb.z)
        guard peak > 1e-12 else { return .white }
        return RGBA(SceneExport.srgb(rgb.x / peak), SceneExport.srgb(rgb.y / peak), SceneExport.srgb(rgb.z / peak))
    }

    static func shrink(_ map: RadianceHDR, to width: Int) -> RadianceHDR {
        let factor = max(map.width / width, 1)
        let outWidth = map.width / factor
        let outHeight = max(map.height / factor, 1)
        var pixels = [Float](repeating: 0, count: outWidth * outHeight * 3)
        for row in 0 ..< outHeight * factor {
            for column in 0 ..< outWidth * factor {
                let from = (row * map.width + column) * 3
                let to = ((row / factor) * outWidth + column / factor) * 3
                for channel in 0 ..< 3 {
                    pixels[to + channel] += map.pixels[from + channel]
                }
            }
        }
        let share = 1 / Float(factor * factor)
        return RadianceHDR(width: outWidth, height: outHeight, pixels: pixels.map { $0 * share })
    }
}
