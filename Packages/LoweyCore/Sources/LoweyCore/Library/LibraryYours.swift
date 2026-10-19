import Foundation
import HmmDocuments

/// A particle effect made in the Effect Studio (L2, D-484): the recipe and its name, kept on this iPad in Yours, placed
/// from Model ▸ Add ▸ Effects like the built-in ones.
public struct SavedEffect: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var recipe: ParticleRecipe
    public var added: Date

    public init(id: String, name: String, recipe: ParticleRecipe, added: Date = Date()) {
        self.id = id
        self.name = name
        self.recipe = recipe
        self.added = added
    }
}

/// A character part made by hand (drawn, modelled, or a set part restyled) saved to Yours (L2, D-484): the part's
/// things as they hang from where it attaches, its job and the side it's made for. It goes onto any character, or any
/// thing, from the character's panel.
public struct SavedPart: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var job: CharacterPart.Job
    /// The part's things, its root at the origin where it attaches.
    public var fragment: SceneFragment
    public var added: Date

    public init(id: String, name: String, job: CharacterPart.Job, fragment: SceneFragment, added: Date = Date()) {
        self.id = id
        self.name = name
        self.job = job
        self.fragment = fragment
        self.added = added
    }
}

/// What a library item is to a pack and to the origins kept beside the library: its kind's word and its id.
public enum LibraryKind: String, Codable, Sendable, CaseIterable {
    case brush, look, material, effect, part, motion, thing

    public var title: String {
        switch self {
        case .brush: "Brush"
        case .look: "Look"
        case .material: "Material"
        case .effect: "Effect"
        case .part: "Part"
        case .motion: "Motion"
        case .thing: "Thing"
        }
    }

    /// The key an item's origin is kept under (`brush:ink-pen`).
    public func key(_ id: String) -> String { "\(rawValue):\(id)" }
}

public extension LibraryManifest {
    /// Where an item came from, when it came in a pack.
    func origin(_ kind: LibraryKind, _ id: String) -> HmmPackOrigin? {
        origins[kind.key(id)]
    }

    /// One of your Looks by id.
    func style(_ id: String) -> LookPreset? { styles.first { $0.id == id } }

    func effect(_ id: String) -> SavedEffect? { effects.first { $0.id == id } }

    func part(_ id: String) -> SavedPart? { parts.first { $0.id == id } }
}
