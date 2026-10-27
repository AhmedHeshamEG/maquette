import Foundation

/// A key and its modifiers, as a person presses it (⌘⇧D). `key` is one lowercased character, or a named key:
/// delete, escape, return, tab, space, up, down, left, right.
public struct HmmKeyCombo: Codable, Hashable, Sendable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public static let namedKeys: [String: String] = [
        "delete": "⌫", "escape": "⎋", "return": "↩", "tab": "⇥", "space": "Space", "up": "↑", "down": "↓", "left": "←", "right": "→"
    ]

    /// The way the menu bar writes it: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + (Self.namedKeys[key] ?? key.uppercased())
    }

    /// A shortcut needs ⌘, ⌃ or ⌥, or a key that types nothing (a bare letter would steal typing).
    public var isUsable: Bool {
        command || control || option || (Self.namedKeys[key] != nil && key != "space")
    }
}

/// One command a keyboard can reach: its id (stable, stored), its name and menu as the menu bar shows them, and the key
/// it comes with.
public struct HmmKeyCommand: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var menu: String
    public var standard: HmmKeyCombo?

    public init(_ id: String, _ title: String, menu: String, _ standard: HmmKeyCombo? = nil) {
        self.id = id
        self.title = title
        self.menu = menu
        self.standard = standard
    }
}

/// The keys a person chose (Settings ▸ Keyboard): changes from the app's own keys only. A key moved onto a command
/// takes it from whichever command had it, which is then left without one until it's given another or reset.
public struct HmmKeyBindings: Codable, Equatable, Sendable {
    /// Command id → the key chosen for it.
    public var chosen: [String: HmmKeyCombo]
    /// Commands whose key was taken away (by a person, or by another command taking it).
    public var cleared: Set<String>

    public init(chosen: [String: HmmKeyCombo] = [:], cleared: Set<String> = []) {
        self.chosen = chosen
        self.cleared = cleared
    }

    public var isDefault: Bool { chosen.isEmpty && cleared.isEmpty }

    /// The key that reaches `command` now.
    public func combo(for command: HmmKeyCommand) -> HmmKeyCombo? {
        if let combo = chosen[command.id] { return combo }
        if cleared.contains(command.id) { return nil }
        return command.standard
    }

    /// The command `combo` reaches now, among `commands`.
    public func command(for combo: HmmKeyCombo, in commands: [HmmKeyCommand]) -> HmmKeyCommand? {
        commands.first { self.combo(for: $0) == combo }
    }

    /// Gives `command` the key `combo` (nil: no key). Returns the commands that lost it.
    @discardableResult
    public mutating func bind(_ command: HmmKeyCommand, to combo: HmmKeyCombo?, among commands: [HmmKeyCommand]) -> [HmmKeyCommand] {
        var losers: [HmmKeyCommand] = []
        if let combo {
            for other in commands where other.id != command.id && self.combo(for: other) == combo {
                set(other, nil)
                losers.append(other)
            }
        }
        set(command, combo)
        return losers
    }

    /// One command back to its own key (which another command may hold: that one loses it).
    @discardableResult
    public mutating func reset(_ command: HmmKeyCommand, among commands: [HmmKeyCommand]) -> [HmmKeyCommand] {
        bind(command, to: command.standard, among: commands)
    }

    private mutating func set(_ command: HmmKeyCommand, _ combo: HmmKeyCombo?) {
        if combo == command.standard {
            chosen[command.id] = nil
            cleared.remove(command.id)
        } else if let combo {
            chosen[command.id] = combo
            cleared.remove(command.id)
        } else {
            chosen[command.id] = nil
            cleared.insert(command.id)
        }
    }

    public static let storageKey = "hmm.keys"

    public static func load(from defaults: UserDefaults = .standard) -> HmmKeyBindings {
        guard let data = defaults.data(forKey: storageKey), let bindings = try? JSONDecoder().decode(Self.self, from: data) else {
            return HmmKeyBindings()
        }
        return bindings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if isDefault {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
