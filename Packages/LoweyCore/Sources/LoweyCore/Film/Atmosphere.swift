import Foundation

/// The air between the camera and the set (F1): haze that the light shows up in, and god rays, the shafts of light a
/// bright sun or a window throws through it. Both are 0…1, 0 = clear; they belong to the Look, so every shot agrees.
public struct Atmosphere: Codable, Hashable, Sendable {
    /// How thick the air is: far things fade toward the haze's colour, and the sun's side of the frame glows.
    public var haze: Double
    /// How strong the shafts are. They stream from the sun (or the brightest lamp in the frame) past whatever blocks it.
    public var godRays: Double
    /// The haze's colour; nil takes the sky's horizon, warmed by the sun.
    public var color: RGBA?

    public init(haze: Double = 0, godRays: Double = 0, color: RGBA? = nil) {
        self.haze = haze
        self.godRays = godRays
        self.color = color
    }

    public var isClear: Bool { haze <= 0 && godRays <= 0 }

    /// The haze's colour for a Look.
    public func resolvedColor(sky: Sky, sunColor: RGBA) -> RGBA {
        if let color { return color }
        return RGBA(sky.horizon.r * 0.7 + sunColor.r * 0.3, sky.horizon.g * 0.7 + sunColor.g * 0.3, sky.horizon.b * 0.7 + sunColor.b * 0.3)
    }

    /// Extinction per metre: at full haze, half the light is gone after 25 m.
    public var density: Double { haze * haze * log(2) / 25 }
}
