import HmmHeld

/// Maquette's held features (CONTEXT §5), the mechanism only: built before launch, aired after it as free updates. Since
/// 0.28 nothing is held (CONTEXT §D.3: everything ships in 1.0), so there are no names; an update that ever held one
/// again would add it here and to `MAQUETTE_HELD` in `project.yml`. Only entry points would ask.
public struct MaquetteHeld: HmmHeldFeature {
    public let rawValue: String

    /// No name is a held feature.
    public init?(rawValue _: String) {
        nil
    }

    public static let allCases: [MaquetteHeld] = []
}

/// This build's held list, read once from the Info.plist.
public enum Held {
    public static let build = HmmHeld<MaquetteHeld>.main()

    /// Whether `feature` can be reached in this build.
    public static func isOn(_ feature: MaquetteHeld) -> Bool {
        build.isOn(feature)
    }
}
