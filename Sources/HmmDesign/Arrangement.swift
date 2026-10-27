import Foundation

/// Which hand holds the Pencil. Left mirrors the canvas's chrome: the two corner clusters swap corners, the sidebar
/// goes to the right edge, the bottom corners swap. Text, icons and time (a timeline reads left to right) don't mirror.
public enum HmmHand: String, CaseIterable, Identifiable, Sendable {
    case right, left

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .right: "Right hand"
        case .left: "Left hand"
        }
    }

    /// The chrome is mirrored.
    public var mirrors: Bool { self == .left }

    /// The key the choice is stored under (`@AppStorage(HmmHand.storageKey)`).
    public static let storageKey = "hmm.hand"

    /// The stored hand; a device that only had "the sidebar on the right" (`legacyKey`) is left-handed.
    public static func current(in defaults: UserDefaults = .standard, legacyKey: String? = nil) -> HmmHand {
        if let raw = defaults.string(forKey: storageKey), let hand = HmmHand(rawValue: raw) { return hand }
        if let legacyKey, defaults.bool(forKey: legacyKey) { return .left }
        return .right
    }

    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

/// The order of a group of buttons and the ones hidden, as a person arranged them (Settings ▸ Your layout). Buttons
/// move only within their group: nothing changes corner. A group's ids come from the app, in the default order; ids
/// the app adds later take their default place among the saved ones, so an update never loses a button.
public struct HmmArrangement: Codable, Equatable, Sendable {
    /// The saved order (may miss ids added since, may hold ids since removed).
    public var order: [String]
    public var hidden: Set<String>

    public init(order: [String] = [], hidden: Set<String> = []) {
        self.order = order
        self.hidden = hidden
    }

    /// Nothing changed from the app's own layout.
    public var isDefault: Bool { order.isEmpty && hidden.isEmpty }

    /// Every id of the group, in the arranged order, hidden ones included (what Settings lists).
    public func ordered(_ ids: [String]) -> [String] {
        let known = Set(ids)
        var result = order.filter { known.contains($0) }
        var seen = Set(result)
        for (index, id) in ids.enumerated() where !seen.contains(id) {
            // After the nearest id that comes before it by default, else first.
            let before = ids[..<index].last { seen.contains($0) }
            let at = before.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: at)
            seen.insert(id)
        }
        return result
    }

    /// What shows: the arranged order without the hidden ids. `fixed` ids can't be hidden (the way home, the way to
    /// Settings), whatever was saved.
    public func visible(_ ids: [String], fixed: Set<String> = []) -> [String] {
        ordered(ids).filter { !hidden.contains($0) || fixed.contains($0) }
    }

    /// Moves `id` by `offset` places (−1 up or left, +1 down or right), within the group.
    public mutating func move(_ id: String, by offset: Int, in ids: [String]) {
        var list = ordered(ids)
        guard let from = list.firstIndex(of: id) else { return }
        let to = max(0, min(list.count - 1, from + offset))
        guard to != from else { return }
        list.remove(at: from)
        list.insert(id, at: to)
        order = list
        settle(ids)
    }

    /// Moves the ids at `source` to `destination`, as a list's drag does (`onMove`).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, in ids: [String]) {
        var list = ordered(ids)
        let moving = source.sorted().map { list[$0] }
        let before = list[..<min(destination, list.count)].filter { !moving.contains($0) }.count
        list.removeAll { moving.contains($0) }
        list.insert(contentsOf: moving, at: min(before, list.count))
        order = list
        settle(ids)
    }

    public mutating func setHidden(_ id: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }

    /// Back to the default order is stored as no order at all.
    private mutating func settle(_ ids: [String]) {
        if order == ids { order = [] }
    }
}

/// Where arrangements live: one JSON value per group in `UserDefaults`, under `hmm.layout.<group>`.
public enum HmmLayoutStore {
    public static let prefix = "hmm.layout."

    public static func arrangement(_ group: String, in defaults: UserDefaults = .standard) -> HmmArrangement {
        guard let data = defaults.data(forKey: prefix + group),
              let arrangement = try? JSONDecoder().decode(HmmArrangement.self, from: data) else { return HmmArrangement() }
        return arrangement
    }

    public static func save(_ arrangement: HmmArrangement, _ group: String, in defaults: UserDefaults = .standard) {
        if arrangement.isDefault {
            defaults.removeObject(forKey: prefix + group)
        } else if let data = try? JSONEncoder().encode(arrangement) {
            defaults.set(data, forKey: prefix + group)
        }
    }

    /// Reset layout: every group's arrangement, the hand and the keys in `extraKeys` (the sidebar's place) go back to
    /// the app's own.
    public static func reset(_ groups: [String], extraKeys: [String] = [], in defaults: UserDefaults = .standard) {
        for group in groups {
            defaults.removeObject(forKey: prefix + group)
        }
        defaults.removeObject(forKey: HmmHand.storageKey)
        for key in extraKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

/// A place along an edge, kept as a fraction: 0 is the middle, −1 the top, +1 the bottom (the sidebar dragged along
/// its edge). The fraction survives a rotation or a Split View, where pixels wouldn't.
public enum HmmEdgePlace {
    /// The offset from the middle for `fraction` when `content` tall sits in `container` tall.
    public static func offset(_ fraction: Double, content: Double, container: Double) -> Double {
        let room = max(0, (container - content) / 2)
        return max(-1, min(1, fraction)) * room
    }

    /// The fraction after dragging by `translation` from `start`.
    public static func fraction(from start: Double, dragged translation: Double, content: Double, container: Double) -> Double {
        let room = max(0, (container - content) / 2)
        guard room > 0 else { return 0 }
        return max(-1, min(1, start + translation / room))
    }
}
