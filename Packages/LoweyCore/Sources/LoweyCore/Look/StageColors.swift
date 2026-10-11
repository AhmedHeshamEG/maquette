import Foundation

/// The colours the stage draws over a scene (the editor layer: the grid, the gizmo's axes, the selection outline),
/// and the arithmetic that keeps them visible on any ground. A blank project opens in the dark studio, and nothing may
/// go invisible on it (CONTEXT §10.10): `StageColorsTests` checks every default against its near-black ground.
public enum StageColors {
    /// The selection outline (the accent's amber).
    public static let selection = RGBA(1, 0.72, 0.28)
    /// The move, turn and size handles, one colour per axis.
    public static let axes: [Axis: RGBA] = [.x: RGBA(0.96, 0.33, 0.36), .y: RGBA(0.45, 0.86, 0.4), .z: RGBA(0.35, 0.58, 1)]
    /// The grid's lines are white over the ground at these strengths, every metre and every five (Editor.metal's
    /// `lw_gridFragment` draws them so).
    public static let gridMinorAlpha = 0.16
    public static let gridMajorAlpha = 0.32

    /// WCAG relative luminance of an sRGB colour.
    public static func luminance(_ color: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    /// WCAG contrast ratio between two colours (1 … 21).
    public static func contrast(_ first: RGBA, _ second: RGBA) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `color` laid over `ground` at `alpha` (blended in linear light, as the GPU does), back in sRGB.
    public static func over(_ color: RGBA, alpha: Double, on ground: RGBA) -> RGBA {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        func encoded(_ channel: Double) -> Double {
            channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
        }
        func mix(_ top: Double, _ bottom: Double) -> Double {
            encoded(linear(top) * alpha + linear(bottom) * (1 - alpha))
        }
        return RGBA(mix(color.r, ground.r), mix(color.g, ground.g), mix(color.b, ground.b))
    }
}
