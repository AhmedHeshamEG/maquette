import Foundation

/// Procreate's palettes (`.swatches`): a zip holding `Swatches.json`, one palette with its name and up to 30 swatches
/// in hue, saturation and brightness (each 0…1; empty slots are null). The app unzips it and hands the JSON here.
public extension HmmPalette {
    /// The palette in a `Swatches.json` (a palette, or a list of them: the first); nil when it isn't one.
    static func procreate(swatchesJSON data: Data) -> HmmPalette? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let palette: [String: Any]? = if let list = json as? [[String: Any]] {
            list.first
        } else {
            json as? [String: Any]
        }
        guard let palette, let swatches = palette["swatches"] as? [Any] else { return nil }
        let colours: [HmmColour] = swatches.compactMap { entry in
            guard let swatch = entry as? [String: Any], let hue = Self.number(swatch["hue"]),
                  let saturation = Self.number(swatch["saturation"]), let brightness = Self.number(swatch["brightness"]) else { return nil }
            return HmmHSB(hue: hue, saturation: saturation, brightness: brightness).rgb
        }
        guard !colours.isEmpty else { return nil }
        let name = (palette["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Procreate palette"
        return HmmPalette(name: name, colours: colours)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
