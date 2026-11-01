import Foundation

/// A feature built before launch and aired later as a free update (CONTEXT §5, "held features"). Each app lists its
/// own (`MaquetteHeld`, `CutawayHeld`) as a `String` enum.
public protocol HmmHeldFeature: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {}

/// Which features this build holds back.
///
/// The list is written into the app's Info.plist at build time (`HmmHeld`, a space-separated list of raw values) from
/// one build setting per configuration: the App Store configuration names what is still held, every other
/// configuration names nothing. The bundle is sealed by its signature, so a store build can't be talked into a held
/// feature by any means; an update airs one by deleting its name from the setting. Swift packages don't see an app
/// target's compilation conditions, which is why the list travels in the bundle and is read once.
///
/// Flags hide making, never reading: only entry points (a row, a button, a menu item, a template, a tool, a lesson)
/// ask. Models, commands, the schema and the journal never do.
public struct HmmHeld<Feature: HmmHeldFeature>: Sendable {
    /// The Info.plist key.
    public static var infoKey: String { "HmmHeld" }

    /// The features held back in this build.
    public let held: Set<Feature>

    public init(held: Set<Feature>) {
        self.held = held
    }

    /// Reads the list from an Info.plist dictionary. Unknown names are ignored (an older app reading a newer list).
    public init(info: [String: Any]?) {
        self.init(list: info?[Self.infoKey] as? String ?? "")
    }

    /// Parses a space- or comma-separated list of raw values.
    public init(list: String) {
        let names = list.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
        held = Set(names.compactMap { Feature(rawValue: String($0)) })
    }

    /// This build's list, from the main bundle.
    public static func main() -> Self {
        Self(info: Bundle.main.infoDictionary)
    }

    /// Whether `feature` can be reached in this build.
    public func isOn(_ feature: Feature) -> Bool {
        !held.contains(feature)
    }

    /// Everything is on (Debug, CI, sideload, Showcase).
    public var holdsNothing: Bool { held.isEmpty }
}
