import Foundation
import HmmDesign
import LoweyCore

/// The groups of buttons a person can arrange (U8, Settings ▸ Your layout): each keeps its corner; inside it, buttons
/// can be put in another order or hidden. Home and Actions always stay (the way home, the way to Settings).
enum ChromeGroup: String, CaseIterable, Identifiable, Sendable {
    /// The top corner for the document and the app: Home, Actions, Look, Library.
    case document
    /// The top corner for making: Model, Draw, Rig, Animate.
    case making
    /// The bottom corner for the view: the views (the cube), the camera, the joystick, snapping.
    case view

    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: "The document's corner"
        case .making: "The making corner"
        case .view: "The view corner"
        }
    }

    /// The buttons, in the app's own order (left to right).
    var ids: [String] {
        switch self {
        case .document: ["home", "actions", "look", "library"]
        case .making: ["model", "draw", "rig", "animate"]
        case .view: ["views", "camera", "joystick", "snap"]
        }
    }

    /// Buttons that can't be hidden.
    var fixed: Set<String> {
        self == .document ? ["home", "actions"] : []
    }

    /// The key its arrangement is stored under (`@AppStorage` reads it as data, so the chrome follows a change at once).
    var storageKey: String { HmmLayoutStore.prefix + rawValue }

    static func label(_ id: String) -> (title: String, systemImage: String) {
        switch id {
        case "home": ("Home", "square.grid.2x2")
        case "actions": ("Actions", "ellipsis.circle")
        case "look": ("Look", "paintpalette")
        case "library": ("Library", "books.vertical")
        case "model": ("Model", "cube")
        case "draw": ("Draw", "pencil.tip")
        case "rig": ("Rig", "figure.arms.open")
        case "animate": ("Animate", "figure.walk.motion")
        case "views": ("Views", "cube.transparent")
        case "camera": ("Camera", "video")
        case "joystick": ("Joystick", "gamecontroller")
        case "snap": ("Snapping", "magnet")
        default: (id, "questionmark")
        }
    }

    /// The arrangement stored as `data` (what `@AppStorage(storageKey)` holds).
    static func arrangement(_ data: Data) -> HmmArrangement {
        (try? JSONDecoder().decode(HmmArrangement.self, from: data)) ?? HmmArrangement()
    }

    /// What shows, in order, for the stored `data`.
    func visible(_ data: Data) -> [String] {
        Self.arrangement(data).visible(ids, fixed: fixed)
    }
}

/// U8's preferences: the layout's extra pieces, your defaults for new projects, your name on notes.
enum YourSettings {
    /// Where the sidebar sits along its edge (`HmmEdgePlace`: 0 the middle, −1 the top, +1 the bottom).
    static let sidebarPlace = "layout.sidebarPlace"
    /// New projects (the + on Home): the set-up, the Look, the units and the brush they start with.
    static let defaultSetUp = "defaults.setUp"
    static let defaultLook = "defaults.look"
    static let defaultUnits = "defaults.units"
    static let defaultBrush = "defaults.brush"
    /// The name review notes are signed with.
    static let yourName = "you.name"

    /// Reset layout: the hand, every group, the sidebar's place. Your defaults and keys are their own pages' to reset.
    static func resetLayout(in defaults: UserDefaults = .standard) {
        HmmLayoutStore.reset(ChromeGroup.allCases.map(\.rawValue), extraKeys: [sidebarPlace, AppSettings.sidebarOnRight], in: defaults)
    }

    /// The hand, reading a device that only had "Sidebar on the right" as left-handed (once; the choice is then kept).
    static func settleHand(in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: HmmHand.storageKey) == nil else { return }
        HmmHand.current(in: defaults, legacyKey: AppSettings.sidebarOnRight).save(in: defaults)
    }

    /// The signature on notes: the name given, else this device's.
    static func name(in defaults: UserDefaults = .standard, device: String) -> String {
        let given = defaults.string(forKey: yourName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return given.isEmpty ? device : given
    }

    /// The set-up the + makes.
    static func setUp(in defaults: UserDefaults = .standard) -> StarterTemplate.Kind {
        defaults.string(forKey: defaultSetUp).flatMap(StarterTemplate.Kind.init(rawValue:)) ?? .blank
    }

    /// The + 's project: the set-up's own template, with your Look and units over it.
    static func template(in defaults: UserDefaults = .standard) -> StarterTemplate {
        var template = StarterTemplate.template(setUp(in: defaults))
        if let look = defaults.string(forKey: defaultLook), LookPreset.all(custom: []).contains(where: { $0.id == look }) {
            template.lookPresetID = look
        }
        if let units = defaults.string(forKey: defaultUnits).flatMap(LengthUnit.init(rawValue:)) { template.workspace.units = units }
        return template
    }
}
