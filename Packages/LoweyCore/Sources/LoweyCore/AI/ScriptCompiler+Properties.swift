import Foundation

// MARK: - Property names a script may write

extension ScriptState {
    /// The names people write for a property, mapped to the one the app keys. A lens in millimetres becomes the field
    /// of view (its values converted), so a zoom keyed as `focalLength` plays instead of being kept and ignored.
    static let propertyAliases: [String: PropertyKey] = [
        "focalLength": .fieldOfView, "lens": .fieldOfView, "mm": .fieldOfView, "fov": .fieldOfView,
        "focus": .focusDistance, "fStop": .aperture,
        "metalness": .metallic, "glow": .emissiveIntensity, "emissiveColor": .emissive,
        "cone": .spotAngle, "coneAngle": .spotAngle, "angle": .spotAngle,
        "range": .lightRange, "lightColour": .lightColor, "colour": .color
    ]

    /// Keys the app stores without a spec (recipes, attachments): a script may still set them by their own name.
    static let unspecifiedKeys: Set<String> = [
        "attachBone", "bendDetail", "blobRecipe", "characterRecipe", "faceRange", "faceRole", "hoseFrom", "hoseRadius",
        "hoseTo", "hoseWrist", "liveHead", "poseLibrary", "rigStandard", "triggers"
    ]

    /// The key a script's `property` names, and how its values convert. An unknown name is refused, never stored.
    func scriptProperty(_ name: String) throws -> (key: PropertyKey, convert: (PropertyValue) -> PropertyValue) {
        let millimetres = ["focalLength", "lens", "mm"].contains(name)
        let key = Self.propertyAliases[name] ?? PropertyKey(name)
        guard key.spec != nil || Self.unspecifiedKeys.contains(key.rawValue) else {
            let close = Self.propertyAliases.keys.filter { $0.lowercased().hasPrefix(name.lowercased().prefix(3)) }.sorted()
            throw fail("unknown property “\(name)”" + (close.isEmpty ? "" : " (did you mean \(close.joined(separator: ", "))?)")
                + " — lowey://actions lists them")
        }
        guard millimetres else { return (key, { $0 }) }
        return (key, { value in
            if case let .float(mm) = value { return .float(CameraLens.fieldOfView(focalLength: max(mm, 1))) }
            return value
        })
    }
}
