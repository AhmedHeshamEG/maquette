import HmmHeld

/// Maquette's held features (CONTEXT §5): built before launch, aired after it as free updates. The App Store
/// configuration lists what is still held in `project.yml` (`MAQUETTE_HELD`); every other configuration holds nothing.
/// Only entry points ask (a row, a button, a menu item); the project format, commands and the renderer never do.
public enum MaquetteHeld: String, HmmHeldFeature {
    /// Live performance (M10): the microphone's mouth, triggers, life, parts, dangle, draggers, takes. Airs as 1.2.
    case livePerformance
    /// Mechanisms (M12): hinges, sliders, gears, motors, springs. Airs as 1.1.
    case mechanisms
    /// AR view and Quick Look sharing (M12). Airs as 1.1.
    case ar
    /// The web layer (M12): HTML pieces in the scene and on the frame. Airs as 1.3.
    case webLayer
}

/// This build's held list, read once from the Info.plist.
public enum Held {
    public static let build = HmmHeld<MaquetteHeld>.main()

    /// Whether `feature` can be reached in this build.
    public static func isOn(_ feature: MaquetteHeld) -> Bool {
        build.isOn(feature)
    }
}
