import Foundation

/// A colour as the picker holds it: sRGB, 0…1 per channel. Pure maths, tested on its own.
public struct HmmColour: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
    }

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    public static let white = HmmColour(red: 1, green: 1, blue: 1)
    public static let black = HmmColour(red: 0, green: 0, blue: 0)

    /// "#RRGGBB".
    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// Reads "#RGB", "#RRGGBB" (the hash is optional, case doesn't matter); nil for anything else.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// How light it looks (Rec. 709 weights on the stored values), for choosing a mark's colour over it.
    public var lightness: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

/// Hue, saturation and brightness (HSV), each 0…1: the disc's angle, its distance from the middle, and the value.
public struct HmmHSB: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        let wrapped = hue - hue.rounded(.down)
        self.hue = wrapped.isFinite ? wrapped : 0
        self.saturation = HmmColour.unit(saturation)
        self.brightness = HmmColour.unit(brightness)
    }

    public init(_ rgb: HmmColour) {
        let high = max(rgb.red, rgb.green, rgb.blue), low = min(rgb.red, rgb.green, rgb.blue)
        let delta = high - low
        var hue = 0.0
        if delta > 1e-9 {
            if high == rgb.red {
                hue = (rgb.green - rgb.blue) / delta
            } else if high == rgb.green {
                hue = (rgb.blue - rgb.red) / delta + 2
            } else {
                hue = (rgb.red - rgb.green) / delta + 4
            }
            hue /= 6
        }
        self.init(hue: hue, saturation: high > 1e-9 ? delta / high : 0, brightness: high)
    }

    public var rgb: HmmColour {
        let h = hue * 6
        let sector = Int(h.rounded(.down)) % 6
        let f = h - h.rounded(.down)
        let v = brightness, s = saturation
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return HmmColour(red: v, green: t, blue: p)
        case 1: return HmmColour(red: q, green: v, blue: p)
        case 2: return HmmColour(red: p, green: v, blue: t)
        case 3: return HmmColour(red: p, green: q, blue: v)
        case 4: return HmmColour(red: t, green: p, blue: v)
        default: return HmmColour(red: v, green: p, blue: q)
        }
    }
}

/// The disc's geometry (Procreate's): hue round the ring, saturation out from the middle of the inner disc, brightness
/// on its own slider. Points are relative to the disc's centre, in units of its radius.
public enum HmmColourDisc {
    /// The ring's inner edge, in units of the disc's radius.
    public static let ringInner = 0.82

    /// The hue at a point (its angle, 0 at the top, clockwise).
    public static func hue(atX x: Double, y: Double) -> Double {
        let angle = atan2(x, -y) / (2 * Double.pi)
        return angle < 0 ? angle + 1 : angle
    }

    /// The saturation at a point inside the inner disc (its distance from the middle, clamped).
    public static func saturation(atX x: Double, y: Double) -> Double {
        min((x * x + y * y).squareRoot() / (ringInner * 0.94), 1)
    }

    /// Where a hue and saturation sit inside the inner disc.
    public static func point(hue: Double, saturation: Double) -> (x: Double, y: Double) {
        let angle = hue * 2 * Double.pi
        let distance = saturation * ringInner * 0.94
        return (sin(angle) * distance, -cos(angle) * distance)
    }

    /// Whether a point is on the hue ring.
    public static func isOnRing(x: Double, y: Double) -> Bool {
        let distance = (x * x + y * y).squareRoot()
        return distance >= ringInner - 0.04 && distance <= 1.06
    }
}

/// The colours used lately, newest first, without repeats (Procreate's history row).
public struct HmmColourHistory: Hashable, Sendable, Codable {
    public private(set) var colours: [HmmColour]
    public static let limit = 10

    public init(colours: [HmmColour] = []) {
        self.colours = Array(colours.prefix(Self.limit))
    }

    /// The colour moves to the front (a near-identical one already there is replaced).
    public mutating func use(_ colour: HmmColour) {
        colours.removeAll { abs($0.red - colour.red) + abs($0.green - colour.green) + abs($0.blue - colour.blue) < 1.5 / 255 }
        colours.insert(colour, at: 0)
        if colours.count > Self.limit { colours.removeLast(colours.count - Self.limit) }
    }
}

/// A saved palette: a name and up to thirty colours.
public struct HmmPalette: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var colours: [HmmColour]
    public static let limit = 30

    public init(id: String = UUID().uuidString, name: String, colours: [HmmColour]) {
        self.id = id
        self.name = name
        self.colours = Array(colours.prefix(Self.limit))
    }

    /// Adds a colour at the end (or does nothing when it's full or already there).
    public mutating func add(_ colour: HmmColour) {
        guard colours.count < Self.limit, !colours.contains(colour) else { return }
        colours.append(colour)
    }
}

/// Everything the picker remembers on this device: the history and the saved palettes, in `UserDefaults` (small,
/// the person's own; apps share it with their pickers by default).
public struct HmmColourMemory: Hashable, Sendable, Codable {
    public var history: HmmColourHistory
    public var palettes: [HmmPalette]

    public init(history: HmmColourHistory = HmmColourHistory(), palettes: [HmmPalette] = []) {
        self.history = history
        self.palettes = palettes
    }

    public static let key = "hmm.colourMemory"

    public static func load(_ defaults: UserDefaults = .standard) -> HmmColourMemory {
        guard let data = defaults.data(forKey: key), let memory = try? JSONDecoder().decode(HmmColourMemory.self, from: data) else {
            return HmmColourMemory()
        }
        return memory
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
